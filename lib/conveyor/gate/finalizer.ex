defmodule Conveyor.Gate.Finalizer do
  @moduledoc """
  Persists gate results and applies post-gate Slice/RunAttempt transitions.
  """

  alias Conveyor.Factory
  alias Conveyor.Factory.GateResult
  alias Conveyor.Factory.Incident
  alias Conveyor.Factory.Project
  alias Conveyor.Factory.RunAttempt
  alias Conveyor.Factory.Slice
  alias Conveyor.Gate
  alias Conveyor.Gate.TrustScore
  alias Conveyor.Genome.BackEdge
  alias Conveyor.SliceLifecycle
  alias Conveyor.TrustBundle

  @spec finalize!(Gate.Result.t(), map(), keyword()) :: map()
  def finalize!(%Gate.Result{} = result, context, opts \\ []) when is_map(context) do
    actor = Keyword.get(opts, :actor, "gate")
    trust = trust_score(result, context)
    gate_result = persist_gate_result!(result, trust)
    run_attempt = run_attempt!(context)
    slice = slice!(context, run_attempt)
    project = project!(context, slice)

    {transition, pass_outputs} =
      cond do
        # ADR-23: a passed gate that the calibrated TrustScore is not confident
        # about abstains — parked for human review, never auto-accepted, and no
        # verified-pass provenance is minted. Opt-in: only fires when the conductor
        # supplied `:trust_evidence`, so existing pass paths are unchanged.
        result.passed? and abstain?(trust) ->
          {abstain_gate!(run_attempt, slice, actor), %{}}

        result.passed? ->
          {pass_gate!(run_attempt, slice, actor), emit_pass_outputs!(context, gate_result, actor)}

        true ->
          {fail_gate!(result, run_attempt, slice, project, actor), %{}}
      end

    %{
      gate_result: gate_result,
      run_attempt: transition.run_attempt,
      slice: transition.slice,
      incident: Map.get(transition, :incident)
    }
    |> maybe_put(:trust_score, trust)
    |> Map.merge(pass_outputs)
  end

  # ADR-23: calibrated trust of a passed gate. Returns nil (no opinion) when the
  # conductor supplied no `:trust_evidence`, leaving the legacy pass path intact.
  defp trust_score(%Gate.Result{passed?: true}, context) do
    case value(context, :trust_evidence) do
      evidence when is_map(evidence) -> TrustScore.evaluate(evidence)
      _ -> nil
    end
  end

  defp trust_score(_result, _context), do: nil

  defp abstain?(%{band: :abstain}), do: true
  defp abstain?(_trust), do: false

  defp abstain_gate!(run_attempt, slice, actor) do
    run_attempt =
      transition_run_attempt(run_attempt, :gate, actor,
        reason: "gate passed but trust score abstained",
        attrs: %{outcome: :abstained}
      )

    slice =
      transition_slice(
        slice,
        :park,
        actor,
        "gate passed but not calibrated-confident; parked for human review"
      )

    %{run_attempt: run_attempt, slice: slice}
  end

  defp emit_pass_outputs!(context, gate_result, actor) do
    provenance_edges = BackEdge.mint!(context, gate_result, actor: actor)
    trust_bundle = TrustBundle.emit!(context, gate_result, provenance_edges: provenance_edges)

    %{
      provenance_edges: provenance_edges,
      trust_bundle: trust_bundle.bundle,
      trust_bundle_artifact: trust_bundle.artifact
    }
  end

  defp persist_gate_result!(result, trust) do
    attrs =
      result.gate_result_attrs
      |> Map.put_new(:level, :slice)
      |> Map.put(:passed, result.passed?)
      |> Map.put(:stages, Enum.map(result.stages, &stage_result_map/1))
      |> maybe_put(:trust_score, trust)

    Ash.create!(GateResult, attrs, domain: Factory)
  end

  defp pass_gate!(run_attempt, slice, actor) do
    run_attempt =
      transition_run_attempt(run_attempt, :gate, actor,
        reason: "gate passed",
        attrs: %{outcome: :accepted}
      )

    slice =
      if slice.state == :in_progress do
        SliceLifecycle.transition!(slice, :gate,
          actor: actor,
          reason: "gate passed",
          required_artifacts?: true,
          gate_stage_complete?: true
        )
      else
        slice
      end

    %{run_attempt: run_attempt, slice: slice}
  end

  defp fail_gate!(result, run_attempt, slice, project, actor) do
    classification = classify_failure(result)

    run_attempt =
      transition_run_attempt(run_attempt, classification.run_attempt_action, actor,
        reason: classification.reason,
        attrs: %{
          outcome: classification.outcome,
          failure_category: classification.failure_category
        }
      )

    slice = transition_slice(slice, classification.slice_action, actor, classification.reason)
    incident = maybe_stop_the_line!(classification, result, project, slice, run_attempt)

    %{run_attempt: run_attempt, slice: slice, incident: incident}
  end

  defp classify_failure(result) do
    categories = Enum.map(result.findings, & &1["category"])

    cond do
      critical_failure?(result) ->
        %{
          run_attempt_action: :fail,
          slice_action: :fail,
          outcome: :rejected,
          failure_category: "critical_gate_failure",
          reason: "critical gate/canary failure"
        }

      Enum.any?(categories, &policy_blocking_category?/1) ->
        %{
          run_attempt_action: :fail,
          slice_action: :policy_block,
          outcome: :policy_blocked,
          failure_category: "policy_violation",
          reason: "gate policy blocked"
        }

      true ->
        %{
          run_attempt_action: :request_rework,
          slice_action: :request_rework,
          outcome: :needs_rework,
          failure_category: "gate_failed",
          reason: "gate requires rework"
        }
    end
  end

  defp critical_failure?(result) do
    result.findings
    |> Enum.any?(fn finding ->
      finding["severity"] == "critical" or
        finding["category"] in ["stale_canary", "canary_false_negative"]
    end)
  end

  defp policy_blocking_category?(category) do
    category in [
      "policy_file_change",
      "policy_invocation_blocked",
      "unredacted_secret",
      "locked_path_touched",
      "protected_path_change"
    ]
  end

  defp transition_run_attempt(run_attempt, action, _actor, opts) do
    attrs = Keyword.get(opts, :attrs, %{})

    try do
      Ash.update!(run_attempt, attrs, action: action, domain: Factory)
    rescue
      _error ->
        Ash.update!(
          run_attempt,
          Map.merge(attrs, status_for_action(action)),
          domain: Factory
        )
    end
  end

  defp status_for_action(:gate), do: %{status: :gated}
  defp status_for_action(:fail), do: %{status: :failed}
  defp status_for_action(:request_rework), do: %{status: :needs_rework}

  defp transition_slice(slice, action, actor, reason) do
    SliceLifecycle.transition!(slice, action, actor: actor, reason: reason)
  rescue
    _error -> Ash.update!(slice, %{state: state_for_action(action)}, domain: Factory)
  end

  defp state_for_action(:fail), do: :failed
  defp state_for_action(:policy_block), do: :policy_blocked
  defp state_for_action(:request_rework), do: :needs_rework
  defp state_for_action(:park), do: :parked

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp maybe_stop_the_line!(
         %{failure_category: "critical_gate_failure"},
         result,
         project,
         slice,
         run_attempt
       ) do
    Ash.create!(
      Incident,
      %{
        project_id: project.id,
        slice_id: slice.id,
        run_attempt_id: run_attempt.id,
        severity: :critical,
        category: "stop_the_line",
        description: "Critical gate/canary failure blocks further sample-project runs.",
        evidence_refs: finding_refs(result.findings),
        status: :open
      },
      domain: Factory
    )
  end

  defp maybe_stop_the_line!(_classification, _result, _project, _slice, _run_attempt), do: nil

  defp finding_refs(findings) do
    findings
    |> Enum.flat_map(fn finding ->
      List.wrap(finding["evidence_refs"]) ++ List.wrap(finding["path"])
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp stage_result_map(stage) do
    %{
      "key" => stage.key,
      "status" => Atom.to_string(stage.status),
      "required" => stage.required?,
      "findings" => stage.findings,
      "evidence_refs" => stage.evidence_refs,
      "input_digests" => stage.input_digests,
      "output_digest" => stage.output_digest,
      "duration_ms" => stage.duration_ms
    }
  end

  defp run_attempt!(context) do
    value(context, :run_attempt) || get_by_id!(RunAttempt, value(context, :run_attempt_id))
  end

  defp slice!(context, run_attempt) do
    value(context, :slice) || get_by_id!(Slice, run_attempt.slice_id)
  end

  defp project!(context, slice) do
    value(context, :project) || get_project_for_slice!(slice)
  end

  defp get_project_for_slice!(slice) do
    epic = get_by_id!(Conveyor.Factory.Epic, slice.epic_id)
    plan = get_by_id!(Conveyor.Factory.Plan, epic.plan_id)
    get_by_id!(Project, plan.project_id)
  end

  defp get_by_id!(resource, id) do
    resource
    |> Ash.read!(domain: Factory)
    |> Enum.find(&(&1.id == id)) ||
      raise ArgumentError, "#{inspect(resource)} #{id} was not found"
  end

  defp value(map, key) when is_map(map),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end
