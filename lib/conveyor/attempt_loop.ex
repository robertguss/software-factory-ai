defmodule Conveyor.AttemptLoop do
  @moduledoc """
  Width-1 multi-attempt conductor for a single Slice.
  """

  require Logger

  alias Conveyor.AttemptBudget
  alias Conveyor.Factory
  alias Conveyor.Factory.DiffPolicy
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.LedgerEvent
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Project
  alias Conveyor.Factory.RunAttempt
  alias Conveyor.Factory.RunSpec
  alias Conveyor.Factory.Slice
  alias Conveyor.Gate
  alias Conveyor.Gate.Finalizer
  alias Conveyor.Gate.TrustEvidence
  alias Conveyor.Jobs.RunGate
  alias Conveyor.Ledger
  alias Conveyor.NegotiatedScope.ScopeAmendment
  alias Conveyor.Planning.StructuralAudit
  alias Conveyor.Recovery.AmendmentRouter
  alias Conveyor.Recovery.ConvergenceSentinel
  alias Conveyor.Recovery.FailureFingerprint
  alias Conveyor.Recovery.ReworkSynthesizer
  alias Conveyor.Recovery.ScopeAmendmentEvaluator
  alias Conveyor.RunAttemptLifecycle
  alias Conveyor.RunSlice
  alias Conveyor.RunSpecForge
  alias Conveyor.SliceLifecycle

  defmodule Result do
    @moduledoc false

    @type t :: %__MODULE__{
            status: atom(),
            attempts: [struct()],
            events: [map()],
            report: map()
          }

    @enforce_keys [:status, :attempts, :events, :report]
    defstruct [:status, :attempts, :events, :report]
  end

  @terminal_outcomes [:accepted, :policy_blocked, :rejected, :abstained]

  @spec run_to_done!(RunAttempt.t() | Ecto.UUID.t(), keyword()) :: Result.t()
  def run_to_done!(run_attempt_or_id, opts \\ []) do
    attempt = run_attempt!(run_attempt_or_id)
    budget = AttemptBudget.new(opts)
    loop(attempt, budget, [], [], nil, opts)
  end

  defp loop(%RunAttempt{} = attempt, budget, attempts, events, prev_fingerprint, opts) do
    run_spec = get_by_id!(RunSpec, attempt.run_spec_id)
    slice_result = run_slice!(attempt, opts)
    gate = run_gate!(run_spec, attempt, slice_result, opts)
    finalization = finalize_gate!(gate, run_spec, attempt, slice_result, opts)
    final_attempt = final_attempt(finalization, attempt)
    attempts = attempts ++ [final_attempt]
    events = events ++ [attempt_event(final_attempt, gate)]

    cond do
      final_attempt.outcome in @terminal_outcomes ->
        result(final_attempt.outcome, attempts, events)

      final_attempt.outcome == :needs_rework ->
        handle_rework(final_attempt, %{
          run_spec: run_spec,
          gate: gate,
          slice_result: slice_result,
          budget: budget,
          attempts: attempts,
          events: events,
          prev_fingerprint: prev_fingerprint,
          fingerprint: FailureFingerprint.compute(gate),
          opts: opts
        })

      true ->
        result(:failed, attempts, events)
    end
  end

  # Decide what a needs-rework attempt becomes, cheapest-abstention first: infra outage (not the
  # work), then convergence stall / no-progress, then a real retry, then budget exhaustion.
  defp handle_rework(final_attempt, state) do
    sentinel =
      sentinel_decision(
        final_attempt,
        state.slice_result,
        state.prev_fingerprint,
        state.fingerprint
      )

    infra_error = infra_error_from(state.slice_result)

    cond do
      # Transient infra exhausted its retries (rt6k.7): the provider was down. Park with a typed
      # reason distinct from rework-exhaustion, before consuming a retry.
      infra_error != nil ->
        infra_park(final_attempt, infra_error, state.attempts, state.events, state.opts)

      # nyrl.2: an out-of-scope diff is a scope NEGOTIATION, not a plain retry. The deterministic
      # evaluator grants (widen + re-run under the amended contract) or denies (park scope_denied).
      # Config-gated + only when a retry slot exists, so the default loop is unchanged.
      scope_amendment_applicable?(final_attempt, state) ->
        handle_scope_amendment(final_attempt, state)

      match?({:park, _}, sentinel) ->
        sentinel_park(
          final_attempt,
          sentinel,
          state.prev_fingerprint,
          state.fingerprint,
          state.attempts,
          state.events,
          state.opts
        )

      AttemptBudget.retry_allowed?(state.budget, length(state.attempts)) ->
        retry_rework(final_attempt, state)

      true ->
        on_budget_exhausted(final_attempt, state.attempts, state.events, state.opts)
    end
  end

  defp retry_rework(final_attempt, state) do
    retry_attempt =
      prepare_retry!(
        final_attempt,
        state.run_spec,
        state.gate,
        state.slice_result,
        state.budget,
        state.attempts,
        state.opts
      )

    rung = AttemptBudget.rung_for_retry(state.budget, retry_attempt.attempt_no)
    event = escalation_event!(final_attempt, retry_attempt, state.gate, rung, state.opts)

    loop(
      retry_attempt,
      state.budget,
      state.attempts,
      state.events ++ [escalation_event(event)],
      state.fingerprint,
      state.opts
    )
  end

  # --- nyrl.2 scope amendment ------------------------------------------------

  # Applicable only when: scope negotiation is enabled, the gate blocked on out_of_scope_path, and a
  # retry slot remains (a grant re-runs, consuming a budgeted attempt — the anti-thrash bound).
  defp scope_amendment_applicable?(_final_attempt, state) do
    scope_amendment_enabled?(state.opts) and
      out_of_scope_paths(state.gate) != [] and
      AttemptBudget.retry_allowed?(state.budget, length(state.attempts))
  end

  defp scope_amendment_enabled?(opts) do
    case Keyword.get(opts, :scope_amendment) do
      nil -> Application.get_env(:conveyor, :scope_amendment, [])[:enabled] == true
      enabled -> enabled == true
    end
  end

  defp handle_scope_amendment(final_attempt, state) do
    diff_policy = current_diff_policy!(final_attempt.slice_id)
    request = build_scope_request(out_of_scope_paths(state.gate), diff_policy, state)

    case ScopeAmendmentEvaluator.evaluate(request) do
      {:grant, grant} ->
        amended_sha =
          ScopeAmendment.apply_grant!(final_attempt, diff_policy, grant, actor: actor(state.opts))

        Logger.info(
          "Scope amendment GRANTED slice=#{final_attempt.slice_id} " <>
            "paths=#{Enum.join(grant.added_globs, ",")}"
        )

        retry_rework(final_attempt, %{
          state
          | opts: Keyword.put(state.opts, :diff_policy_sha256, amended_sha)
        })

      {:deny, denial} ->
        scope_denied_park(final_attempt, denial, state)
    end
  end

  # The offending paths from the diff-scope gate finding (nyrl.2 reads only the blocking violations;
  # always_allowed grants are info-level notes, not out_of_scope_path).
  defp out_of_scope_paths(%Gate.Result{} = gate) do
    gate.findings
    |> Enum.filter(&(&1["category"] == "out_of_scope_path"))
    |> Enum.flat_map(&(&1["paths"] || []))
    |> Enum.uniq()
  end

  defp build_scope_request(offending, %DiffPolicy{} = diff_policy, state) do
    %{
      offending_paths: offending,
      allowed_path_globs: diff_policy.allowed_path_globs || [],
      protected_path_globs: diff_policy.protected_path_globs || [],
      allowlist_globs: Keyword.get(state.opts, :scope_allowlist, scope_allowlist(diff_policy)),
      max_extra_files:
        Keyword.get(state.opts, :max_amendment_files, default_max_amendment_files()),
      rationale: scope_rationale(state.slice_result)
    }
  end

  # The eligible-for-grant patterns default to the profile's always-allowed classes (a project that
  # declares no amendment allowlist can grant nothing — fail closed).
  defp scope_allowlist(%DiffPolicy{always_allowed_path_classes: classes}) when is_list(classes) do
    Enum.flat_map(classes, &(&1["globs"] || []))
  end

  defp scope_allowlist(_diff_policy), do: []

  defp default_max_amendment_files do
    Application.get_env(:conveyor, :scope_amendment, [])[:max_extra_files] || 2
  end

  # The agent's stated rationale (audit-only; the evaluator never decides on it). Optional — a run
  # that supplies none evaluates with nil (the prompt-protocol field is a later refinement).
  defp scope_rationale(%{output: output}) when is_map(output), do: output["scope_rationale"]
  defp scope_rationale(_slice_result), do: nil

  defp current_diff_policy!(slice_id) do
    slice = get_by_id!(Slice, slice_id)
    policies = Ash.read!(DiffPolicy, domain: Factory)

    Enum.find(policies, &(&1.id == slice.diff_policy_id)) ||
      Enum.find(policies, &(&1.slice_id == slice_id))
  end

  defp scope_denied_park(final_attempt, denial, state) do
    ledger_event = scope_denied_event!(final_attempt, denial, state.opts)

    Logger.warning(
      "Scope amendment DENIED slice=#{final_attempt.slice_id}: #{denial.violated_bound} " <>
        "paths=#{Enum.join(denial.offending, ",")}"
    )

    summary = scope_denied_summary(ledger_event, denial)
    result(:scope_denied, state.attempts, state.events ++ [summary])
  end

  defp scope_denied_event!(final_attempt, denial, opts) do
    project = project_for_attempt!(final_attempt)

    Ledger.write!(%{
      project_id: project.id,
      slice_id: final_attempt.slice_id,
      run_attempt_id: final_attempt.id,
      idempotency_key: "scope.amendment_denied:#{final_attempt.id}",
      type: "scope.amendment_denied",
      payload: %{
        "actor" => actor(opts),
        "park_reason" => "scope_denied",
        "violated_bound" => Atom.to_string(denial.violated_bound),
        "offending_paths" => denial.offending,
        "detail" => denial.detail
      }
    })
  end

  defp scope_denied_summary(%LedgerEvent{} = event, denial) do
    %{
      "status" => "scope_denied",
      "park_reason" => "scope_denied",
      "finding_categories" => ["scope_denied"],
      "violated_bound" => Atom.to_string(denial.violated_bound),
      "offending_paths" => denial.offending,
      "ledger_event_id" => event.id
    }
  end

  defp actor(opts), do: Keyword.get(opts, :actor, "attempt-loop")

  # Convergence sentinel (rt6k.3): only meaningful for a rework outcome. Empty diff => no
  # progress; identical failure fingerprint to the prior attempt => convergence stall.
  defp sentinel_decision(%{outcome: :needs_rework}, slice_result, prev_fingerprint, fingerprint) do
    ConvergenceSentinel.decide(%{
      diff_empty?: diff_empty?(slice_result),
      prev_fingerprint: prev_fingerprint,
      current_fingerprint: fingerprint
    })
  end

  defp sentinel_decision(_final_attempt, _slice_result, _prev_fingerprint, _fingerprint),
    do: :continue

  defp sentinel_park(
         final_attempt,
         {:park, reason},
         prev_fingerprint,
         fingerprint,
         attempts,
         events,
         opts
       ) do
    ledger_event = convergence_event!(final_attempt, reason, prev_fingerprint, fingerprint, opts)

    Logger.warning(
      "Convergence sentinel parked slice #{final_attempt.slice_id}: #{reason} " <>
        "(fingerprint=#{fingerprint}, attempts=#{length(attempts)})"
    )

    summary = convergence_summary_event(ledger_event, reason, fingerprint)
    base = result(:convergence_parked, attempts, events ++ [summary])
    %Result{base | report: Map.put(base.report, "sentinel_park", reason)}
  end

  # rt6k.7: an infra-exhausted attempt surfaces as slice output metadata (adapter -> station).
  defp infra_error_from(%{output: output}) when is_map(output) do
    case output["infra_error"] do
      %{} = infra -> infra
      _other -> nil
    end
  end

  defp infra_error_from(_slice_result), do: nil

  defp infra_park(final_attempt, infra_error, attempts, events, opts) do
    ledger_event = infra_error_event!(final_attempt, infra_error, opts)
    class = infra_error["class"]

    Logger.warning(
      "attempt parked as infra_error: class=#{class} retries=#{infra_error["retries"]} " <>
        "slice=#{final_attempt.slice_id} — provider failure, not consuming a rework attempt"
    )

    summary = infra_summary_event(ledger_event, infra_error)
    base = result(:infra_error, attempts, events ++ [summary])
    %Result{base | report: Map.put(base.report, "infra_error_class", class)}
  end

  defp infra_error_event!(final_attempt, infra_error, opts) do
    project = project_for_attempt!(final_attempt)
    actor = Keyword.get(opts, :actor, "attempt-loop")

    Ledger.write!(%{
      project_id: project.id,
      slice_id: final_attempt.slice_id,
      run_attempt_id: final_attempt.id,
      idempotency_key: "infra_error:#{final_attempt.id}",
      type: "attempt.infra_error",
      payload: %{
        "actor" => actor,
        "run_attempt_id" => final_attempt.id,
        "attempt_no" => final_attempt.attempt_no,
        "class" => infra_error["class"],
        "retries" => infra_error["retries"]
      }
    })
  end

  defp infra_summary_event(%LedgerEvent{} = event, infra_error) do
    %{
      "status" => "infra_error",
      "infra_error_class" => infra_error["class"],
      "retries" => infra_error["retries"],
      "ledger_event_id" => event.id
    }
  end

  defp convergence_event!(final_attempt, reason, prev_fingerprint, fingerprint, opts) do
    project = project_for_attempt!(final_attempt)
    actor = Keyword.get(opts, :actor, "attempt-loop")

    Ledger.write!(%{
      project_id: project.id,
      slice_id: final_attempt.slice_id,
      run_attempt_id: final_attempt.id,
      idempotency_key: "convergence_parked:#{final_attempt.id}:#{reason}",
      type: "attempt.convergence_parked",
      payload: %{
        "actor" => actor,
        "run_attempt_id" => final_attempt.id,
        "attempt_no" => final_attempt.attempt_no,
        "reason" => reason,
        "current_fingerprint" => fingerprint,
        "previous_fingerprint" => prev_fingerprint
      }
    })
  end

  defp convergence_summary_event(%LedgerEvent{} = event, reason, fingerprint) do
    %{
      "status" => "convergence_parked",
      "sentinel_reason" => reason,
      "current_fingerprint" => fingerprint,
      "previous_fingerprint" => event.payload["previous_fingerprint"],
      "ledger_event_id" => event.id
    }
  end

  # An attempt made no progress when it changed no files. Only park on an explicit empty
  # changed-file list; an unknown/absent signal is conservatively treated as progress.
  defp diff_empty?(%{output: output}) when is_map(output) do
    case changed_files(output) do
      files when is_list(files) -> files == []
      :unknown -> false
    end
  end

  defp diff_empty?(_slice_result), do: false

  defp changed_files(output) do
    patch_set = output["patch_set"]

    cond do
      is_list(output["changed_files"]) -> output["changed_files"]
      is_map(patch_set) and is_list(patch_set["changed_files"]) -> patch_set["changed_files"]
      true -> :unknown
    end
  end

  defp result(status, attempts, events) do
    %Result{
      status: status,
      attempts: attempts,
      events: events,
      report: %{
        "schema_version" => "conveyor.attempt_loop@1",
        "status" => Atom.to_string(status),
        "attempt_count" => length(attempts),
        "rework_recovered" =>
          status == :accepted and Enum.any?(events, &Map.has_key?(&1, "rung")),
        "rework_feedback_categories" =>
          events
          |> Enum.flat_map(&List.wrap(&1["finding_categories"]))
          |> Enum.uniq()
          |> Enum.sort()
      }
    }
  end

  # ADR-26: the code could not satisfy the contract within the rework budget. A
  # hand-authored plan reaches the serial loop WITHOUT a structural audit
  # (PlanRunner skips it), so before parking as a plain exhaustion we re-audit the
  # *contract*. If it is structurally broken, no amount of rework can pass it — we
  # surface a human-review amendment proposal instead of a silent rework death-
  # spiral. A clean contract falls straight through to the existing exhaustion park.
  defp on_budget_exhausted(final_attempt, attempts, events, opts) do
    case audit_contract!(final_attempt, opts) do
      {:amend, proposal} ->
        ledger_event = amendment_event!(final_attempt, proposal, opts)
        amended_result(attempts, events ++ [amendment_event(ledger_event, proposal)], proposal)

      :rework ->
        result(:attempt_budget_exhausted, attempts, events)
    end
  end

  # Injectable `:contract_audit` seam for deterministic tests; the default runs the
  # real StructuralAudit on the plan's normalized contract and routes via ADR-26.
  defp audit_contract!(final_attempt, opts) do
    case Keyword.get(opts, :contract_audit) do
      fun when is_function(fun, 1) ->
        fun.(final_attempt)

      nil ->
        plan = plan_for_attempt!(final_attempt)
        findings = StructuralAudit.audit(plan.normalized_contract || %{}).findings
        AmendmentRouter.route(findings, plan_id: plan.id)
    end
  end

  defp amended_result(attempts, events, proposal) do
    base = result(:amendment_proposed, attempts, events)
    %Result{base | report: Map.put(base.report, "amendment_proposal", proposal)}
  end

  defp amendment_event!(final_attempt, proposal, opts) do
    project = project_for_attempt!(final_attempt)
    actor = Keyword.get(opts, :actor, "attempt-loop")

    Ledger.write!(%{
      project_id: project.id,
      slice_id: final_attempt.slice_id,
      run_attempt_id: final_attempt.id,
      idempotency_key: "amendment_proposed:#{final_attempt.id}",
      type: "plan.amendment_proposed",
      payload: %{
        "actor" => actor,
        "run_attempt_id" => final_attempt.id,
        "dispute_kind" => proposal["dispute_kind"],
        "status" => proposal["status"],
        "affected_refs" => proposal["affected_refs"]
      }
    })
  end

  defp amendment_event(%LedgerEvent{} = event, proposal) do
    %{
      "status" => "amendment_proposed",
      "dispute_kind" => proposal["dispute_kind"],
      "affected_refs" => proposal["affected_refs"],
      "finding_categories" => amendment_finding_categories(proposal),
      "ledger_event_id" => event.id
    }
  end

  defp amendment_finding_categories(proposal) do
    proposal
    |> Map.get("affected_refs", [])
    |> Enum.map(& &1["kind"])
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp prepare_retry!(final_attempt, run_spec, gate, slice_result, budget, attempts, opts) do
    actor = Keyword.get(opts, :actor, "attempt-loop")

    synthesis =
      final_attempt
      |> slice_for_attempt!()
      |> synthesize_rework!(gate, slice_result, actor, final_attempt.attempt_no + 1)

    prior_findings = synthesis.prior_findings
    log_threaded_findings(final_attempt, prior_findings)
    mark_ready!(final_attempt, actor)

    rung = AttemptBudget.rung_for_retry(budget, length(attempts) + 1)
    retry_spec = forge_retry_run_spec!(final_attempt, run_spec, rung, prior_findings, opts)

    create_retry_attempt!(final_attempt, retry_spec, opts)
  end

  defp log_threaded_findings(final_attempt, prior_findings) do
    count = prior_findings |> Map.get("findings", []) |> length()

    Logger.info(
      "Threaded prior findings into retry for slice #{final_attempt.slice_id} (count=#{count})"
    )
  end

  defp synthesize_rework!(slice, gate, slice_result, actor, next_attempt_no) do
    ReworkSynthesizer.synthesize(slice, gate,
      actor: actor,
      output: slice_output(slice_result),
      attempt_no: next_attempt_no
    )
  end

  defp slice_output(%{output: output}) when is_map(output), do: output
  defp slice_output(_slice_result), do: nil

  defp mark_ready!(final_attempt, actor) do
    final_attempt
    |> slice_for_attempt!()
    |> SliceLifecycle.transition!(:mark_ready,
      actor: actor,
      reason: "trusted gate findings synthesized for rework"
    )
  end

  defp forge_retry_run_spec!(final_attempt, run_spec, rung, prior_findings, opts) do
    case Keyword.get(opts, :forge_run_spec) do
      fun when is_function(fun, 3) ->
        fun.(final_attempt, run_spec, rung)

      nil ->
        RunSpecForge.forge_retry!(final_attempt, run_spec,
          rung: rung,
          prior_findings: prior_findings,
          # nyrl.2: a granted amendment widened the DiffPolicy; thread its sha (else preserved).
          diff_policy_sha256: Keyword.get(opts, :diff_policy_sha256)
        )
    end
  end

  defp create_retry_attempt!(final_attempt, retry_spec, opts) do
    case Keyword.get(opts, :create_retry_attempt) do
      fun when is_function(fun, 2) ->
        fun.(final_attempt, retry_spec)

      nil ->
        RunAttemptLifecycle.create_retry_attempt!(final_attempt, retry_spec,
          actor: Keyword.get(opts, :actor, "attempt-loop"),
          reason: "retry gate rework"
        )
    end
  end

  defp run_slice!(attempt, opts) do
    case Keyword.get(opts, :run_slice) do
      fun when is_function(fun, 1) -> fun.(attempt)
      nil -> RunSlice.run!(attempt, Keyword.take(opts, [:actor, :blob_root]))
    end
  end

  defp run_gate!(run_spec, attempt, slice_result, opts) do
    case Keyword.get(opts, :run_gate) do
      fun when is_function(fun, 3) ->
        fun.(run_spec, attempt, slice_result)

      nil ->
        RunGate.run_gate_only!(
          %{
            run_attempt_id: attempt.id,
            run_spec: run_spec,
            verification_result: slice_result.output["verification_result"]
          },
          Keyword.get(opts, :gate_stages, [Conveyor.Gate.Stages.TestExecution]),
          gate_code_sha256: Keyword.get(opts, :gate_code_sha256, digest("gate")),
          policy_sha256: run_spec.policy_sha256,
          contract_lock_sha256: run_spec.contract_lock_sha256
        )
    end
  end

  defp finalize_gate!(gate, run_spec, attempt, slice_result, opts) do
    case Keyword.get(opts, :finalize_gate) do
      fun when is_function(fun, 3) ->
        fun.(gate, run_spec, attempt)

      nil ->
        Finalizer.finalize!(
          gate,
          %{
            run_attempt: attempt,
            run_spec: run_spec,
            trust_evidence: trust_evidence(slice_result)
          },
          actor: Keyword.get(opts, :actor, "attempt-loop")
        )
    end
  end

  # ADR-23: thread the slice run's calibration/baseline signals so a passed-but-
  # unconfident attempt abstains. nil => no evidence => legacy auto-accept.
  defp trust_evidence(%{output: output}) when is_map(output),
    do: TrustEvidence.from_run_output(output)

  defp trust_evidence(_slice_result), do: nil

  defp final_attempt(finalization, fallback) do
    case value(finalization, :run_attempt) do
      %RunAttempt{} = run_attempt -> run_attempt
      _missing -> get_by_id!(RunAttempt, fallback.id)
    end
  end

  defp attempt_event(%RunAttempt{} = attempt, %Gate.Result{} = gate) do
    %{
      "attempt_no" => attempt.attempt_no,
      "outcome" => Atom.to_string(attempt.outcome),
      "status" => Atom.to_string(attempt.status),
      "finding_categories" => finding_categories(gate)
    }
  end

  defp escalation_event!(prior_attempt, retry_attempt, gate, rung, opts) do
    project = project_for_attempt!(retry_attempt)
    actor = Keyword.get(opts, :actor, "attempt-loop")
    rung_name = Map.fetch!(rung, "rung")

    Ledger.write!(%{
      project_id: project.id,
      slice_id: retry_attempt.slice_id,
      run_attempt_id: retry_attempt.id,
      idempotency_key: "attempt_escalated:#{prior_attempt.id}:#{retry_attempt.id}:#{rung_name}",
      type: "attempt.escalated",
      payload: %{
        "actor" => actor,
        "previous_run_attempt_id" => prior_attempt.id,
        "run_attempt_id" => retry_attempt.id,
        "attempt_no" => retry_attempt.attempt_no,
        "rung" => rung_name,
        "finding_categories" => finding_categories(gate),
        "previous_outcome" => Atom.to_string(prior_attempt.outcome)
      }
    })
  end

  defp escalation_event(%LedgerEvent{} = event) do
    %{
      "attempt_no" => event.payload["attempt_no"],
      "rung" => event.payload["rung"],
      "finding_categories" => event.payload["finding_categories"]
    }
  end

  defp finding_categories(%Gate.Result{} = gate) do
    gate.findings
    |> Enum.map(&(&1["category"] || &1[:category]))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp run_attempt!(%RunAttempt{} = attempt), do: attempt
  defp run_attempt!(id), do: get_by_id!(RunAttempt, id)

  defp slice_for_attempt!(%RunAttempt{} = attempt), do: get_by_id!(Slice, attempt.slice_id)

  defp project_for_attempt!(%RunAttempt{} = attempt) do
    plan = plan_for_attempt!(attempt)
    get_by_id!(Project, plan.project_id)
  end

  defp plan_for_attempt!(%RunAttempt{} = attempt) do
    slice = get_by_id!(Slice, attempt.slice_id)
    epic = get_by_id!(Epic, slice.epic_id)
    get_by_id!(Plan, epic.plan_id)
  end

  defp get_by_id!(resource, id) do
    resource
    |> Ash.read!(domain: Factory)
    |> Enum.find(&(&1.id == id)) ||
      raise ArgumentError, "#{inspect(resource)} #{id} was not found"
  end

  defp value(map, key) when is_map(map), do: Map.get(map, key, Map.get(map, to_string(key)))

  defp digest(label), do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, label), case: :lower)
end
