defmodule Conveyor.Planning.SerialDriver do
  @moduledoc """
  Width-1 driver for executing a frozen pilot selection serially.
  """

  alias Conveyor.AttemptLoop
  alias Conveyor.CanonicalJson
  alias Conveyor.ContractEvolution
  alias Conveyor.Factory

  alias Conveyor.Factory.{
    AgentBrief,
    Artifact,
    ContractLock,
    DiffPolicy,
    Evidence,
    PatchSet,
    RunAttempt,
    Slice,
    TestPack
  }

  alias Conveyor.Gate
  alias Conveyor.Gate.Finalizer
  alias Conveyor.Gate.TrustEvidence
  alias Conveyor.Jobs.RunGate
  alias Conveyor.Planning.PilotExecution
  alias Conveyor.Planning.RunSpecAssembler
  alias Conveyor.RunSlice

  @default_gate_stages [
    Conveyor.Gate.Stages.ContractLock,
    Conveyor.Gate.Stages.DiffScope,
    Conveyor.Gate.Stages.SecretSafety,
    Conveyor.Gate.Stages.TestExecution
  ]

  defmodule Result do
    @moduledoc "Serial driver execution result."

    @type t :: %__MODULE__{
            status: :passed | :halted,
            order: [String.t()],
            events: [map()],
            report: map()
          }

    @enforce_keys [:status, :order, :events, :report]
    defstruct [:status, :order, :events, :report]
  end

  @spec run!(map(), keyword()) :: Result.t()
  def run!(input, opts \\ []) when is_map(input) do
    work_graph = value(input, :work_graph) || input
    selected_slice_ids = list(input, :selected_slice_ids)
    order = topo_order(work_graph, selected_slice_ids)

    {status, events} =
      Enum.reduce_while(order, {:passed, []}, fn slice_key, {_status, events} ->
        event = run_one!(slice_key, work_graph, length(events) + 1, opts)
        next_events = events ++ [event]

        if event["status"] == "passed" do
          {:cont, {:passed, next_events}}
        else
          {:halt, {:halted, next_events}}
        end
      end)

    report =
      PilotExecution.summarize(%{
        implementation_width: 1,
        selected_slice_ids: order,
        events: events
      })
      |> Map.merge(replay_report(order, events))

    %Result{status: status, order: order, events: events, report: report}
  end

  defp replay_report(order, events) do
    digest =
      CanonicalJson.digest(%{
        "schema_version" => "conveyor.serial_replay@1",
        "serial_order" => order,
        "events" => Enum.map(events, &normalize_replay_event/1)
      })

    %{
      "replay_digest" => digest,
      "replay_fidelity" => %{
        "schema_version" => "conveyor.replay_fidelity@1",
        "status" => "matched",
        "digest" => digest,
        "event_count" => length(events)
      }
    }
  end

  defp normalize_replay_event(event) do
    %{
      "slice_id" => value(event, :slice_id),
      "sequence" => value(event, :sequence),
      "status" => value(event, :status),
      "gate_result" => value(event, :gate_result),
      "run_attempt_outcome" => value(event, :run_attempt_outcome),
      "findings" => event |> list(:findings) |> Enum.map(&to_string/1)
    }
  end

  defp run_one!(slice_key, work_graph, sequence, opts) do
    single_slice_graph = single_slice_graph!(work_graph, slice_key)

    case interrogate_slice(slice_key, single_slice_graph, sequence, opts) do
      {:park, event} ->
        event

      :continue ->
        run_spec = assemble_run_spec!(slice_key, single_slice_graph, opts)
        run_attempt = create_run_attempt!(run_spec, opts)

        if rework_enabled?(opts) do
          run_one_with_rework!(slice_key, sequence, run_spec, run_attempt, opts)
        else
          run_one_single_attempt!(slice_key, sequence, run_spec, run_attempt, opts)
        end
    end
  end

  # Default (keystone) path — a single attempt, then park on non-accept. Behaviour
  # is UNCHANGED from before M2(b); rework is strictly opt-in (see rework_enabled?/1).
  defp run_one_single_attempt!(slice_key, sequence, run_spec, run_attempt, opts) do
    slice_result = run_slice!(run_attempt, opts)
    gate = run_gate!(run_spec, run_attempt, slice_result, opts)
    finalization = finalize_gate!(gate, run_spec, run_attempt, slice_result, opts)

    passed? =
      slice_result.status == :succeeded and gate_passed?(gate) and accepted?(finalization)

    if passed? do
      advance_workspace_base!(run_spec, slice_key, finalization, opts)
    end

    %{
      "slice_id" => slice_key,
      "sequence" => sequence,
      "status" => if(passed?, do: "passed", else: "parked"),
      "gate_result" => if(passed?, do: "first_pass", else: "eventual_pending"),
      "run_attempt_outcome" => final_outcome(finalization),
      "findings" => finding_categories(gate)
    }
  end

  # M2(b): opt-in rework-on-fail via `AttemptLoop` — a non-accepted slice reworks
  # within a bounded budget instead of parking + halting the plan. We INJECT this
  # driver's `run_slice!`/`run_gate!` (so the rich gate context + 4 wired stages are
  # preserved; AttemptLoop's own defaults are thinner) and let AttemptLoop use its
  # default finalize (== `default_finalize_gate!`) + the real ReworkSynthesizer/
  # RunSpecForge retry path. Enable with `rework: true` (+ optional `max_attempts`).
  defp run_one_with_rework!(slice_key, sequence, run_spec, run_attempt, opts) do
    loop_opts =
      opts
      |> Keyword.put(:run_slice, fn attempt -> run_slice!(attempt, opts) end)
      |> Keyword.put(:run_gate, fn rs, attempt, sr -> run_gate!(rs, attempt, sr, opts) end)
      |> Keyword.put_new(:actor, "serial-driver")
      |> Keyword.put_new(:max_attempts, 3)

    loop_result = AttemptLoop.run_to_done!(run_attempt, loop_opts)
    passed? = loop_result.status == :accepted
    last_attempt = List.last(loop_result.attempts)

    if passed? do
      advance_workspace_base!(run_spec, slice_key, loop_result, opts)
    end

    %{
      "slice_id" => slice_key,
      "sequence" => sequence,
      "status" => if(passed?, do: "passed", else: "parked"),
      "gate_result" => rework_gate_label(passed?, loop_result),
      "run_attempt_outcome" => last_attempt && last_attempt.outcome,
      "findings" => loop_findings(loop_result),
      "attempt_count" => loop_result.report["attempt_count"]
    }
  end

  defp rework_enabled?(opts), do: Keyword.get(opts, :rework, false) == true

  defp rework_gate_label(false, _loop_result), do: "eventual_pending"

  defp rework_gate_label(true, loop_result) do
    if loop_result.report["rework_recovered"], do: "eventual_pass", else: "first_pass"
  end

  defp loop_findings(loop_result) do
    loop_result.events |> List.last(%{}) |> Map.get("finding_categories", [])
  end

  defp interrogate_slice(slice_key, single_slice_graph, sequence, opts) do
    case Keyword.get(opts, :interrogation_preflight) do
      fun when is_function(fun, 2) ->
        fun.(slice_key, single_slice_graph)
        |> interrogation_event(slice_key, sequence)

      _missing ->
        :continue
    end
  end

  defp interrogation_event(batch, slice_key, sequence) do
    if value(batch, :status) in [:questions_required, "questions_required"] do
      {:park,
       %{
         "slice_id" => slice_key,
         "sequence" => sequence,
         "status" => "parked",
         "gate_result" => "eventual_pending",
         "run_attempt_outcome" => :parked,
         "findings" => ["clarification", "interrogator_fired"],
         "interrogation" => %{
           "status" => "questions_required",
           "question_count" => length(list(batch, :questions))
         }
       }}
    else
      :continue
    end
  end

  defp assemble_run_spec!(slice_key, single_slice_graph, opts) do
    case Keyword.get(opts, :assemble_run_spec) do
      fun when is_function(fun, 2) ->
        fun.(slice_key, single_slice_graph)

      nil ->
        slice = slice_for!(slice_key, opts)

        assembler_opts =
          opts
          |> Keyword.get(:run_spec_opts, [])
          |> Keyword.merge(work_graph: single_slice_graph)
          |> maybe_put(:patch_ref, patch_ref_for(slice_key, opts))

        RunSpecAssembler.assemble!(slice, assembler_opts)
    end
  end

  defp create_run_attempt!(run_spec, opts) do
    case Keyword.get(opts, :create_run_attempt) do
      fun when is_function(fun, 1) ->
        fun.(run_spec)

      nil ->
        Ash.create!(
          RunAttempt,
          %{
            slice_id: run_spec.slice_id,
            run_spec_id: run_spec.id,
            attempt_no: run_spec.attempt_no,
            base_commit: run_spec.base_commit,
            status: :planned,
            outcome: :none,
            orchestrator_version: Keyword.get(opts, :orchestrator_version, "conveyor@0.1.0"),
            trace_id: Keyword.get(opts, :trace_id, "serial-driver-#{run_spec.id}")
          },
          domain: Factory
        )
    end
  end

  defp run_slice!(run_attempt, opts) do
    case Keyword.get(opts, :run_slice) do
      fun when is_function(fun, 1) -> fun.(run_attempt)
      nil -> RunSlice.run!(run_attempt, run_slice_opts(opts))
    end
  end

  defp run_slice_opts(opts) do
    opts
    |> Keyword.take([:actor, :blob_root])
    |> maybe_put(:blob_root, Keyword.get(Keyword.get(opts, :run_spec_opts, []), :blob_root))
  end

  defp run_gate!(run_spec, run_attempt, slice_result, opts) do
    case Keyword.get(opts, :run_gate) do
      fun when is_function(fun, 3) ->
        fun.(run_spec, run_attempt, slice_result)

      nil ->
        context =
          %{
            run_attempt_id: run_attempt.id,
            run_attempt: run_attempt,
            run_spec: run_spec,
            verification_result: slice_result.output["verification_result"]
          }
          |> Map.merge(default_gate_context(run_spec, run_attempt, slice_result))
          |> Map.merge(extra_gate_context(run_spec, run_attempt, slice_result, opts))

        RunGate.run_gate_only!(
          context,
          Keyword.get(opts, :gate_stages, @default_gate_stages),
          gate_code_sha256: Keyword.get(opts, :gate_code_sha256, digest("gate")),
          policy_sha256: run_spec.policy_sha256,
          contract_lock_sha256: run_spec.contract_lock_sha256
        )
    end
  end

  defp default_gate_context(run_spec, run_attempt, slice_result) do
    patch_set = patch_set_for(slice_result)
    evidence = evidence_for(slice_result)
    contract = contract_for(run_spec)

    %{
      agent_brief: contract.agent_brief,
      artifacts: artifacts_for(run_attempt.id),
      contract_lock: contract.contract_lock,
      diff_policy: diff_policy_for(run_attempt.slice_id),
      evidence: evidence,
      patch_set: patch_set,
      security_findings: value(slice_result.output, :security_findings, []),
      test_pack: contract.test_pack
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp extra_gate_context(run_spec, run_attempt, slice_result, opts) do
    case Keyword.get(opts, :gate_context) do
      fun when is_function(fun, 3) -> fun.(run_spec, run_attempt, slice_result)
      context when is_map(context) -> context
      _missing -> %{}
    end
  end

  defp patch_set_for(slice_result) do
    PatchSet
    |> find_by_id(value(slice_result.output, :patch_set_id))
  end

  defp evidence_for(slice_result) do
    Evidence
    |> find_by_id(value(slice_result.output, :evidence_id))
  end

  defp contract_for(run_spec) do
    contract_lock =
      ContractLock
      |> Ash.read!(domain: Factory)
      |> Enum.find(&(ContractEvolution.contract_lock_sha256(&1) == run_spec.contract_lock_sha256))

    agent_brief = find_by_id(AgentBrief, contract_lock && contract_lock.agent_brief_id)

    test_pack =
      TestPack
      |> Ash.read!(domain: Factory)
      |> Enum.find(
        &(&1.slice_id == run_spec.slice_id and &1.test_pack_sha256 == run_spec.test_pack_sha256)
      )

    %{agent_brief: agent_brief, contract_lock: contract_lock, test_pack: test_pack}
  end

  defp diff_policy_for(slice_id) do
    slice = get_by_id!(Slice, slice_id)

    find_by_id(DiffPolicy, slice.diff_policy_id) ||
      DiffPolicy
      |> Ash.read!(domain: Factory)
      |> Enum.find(&(&1.slice_id == slice_id))
  end

  defp artifacts_for(run_attempt_id) do
    Artifact
    |> Ash.read!(domain: Factory)
    |> Enum.filter(&(&1.run_attempt_id == run_attempt_id))
  end

  defp find_by_id(_resource, nil), do: nil

  defp find_by_id(resource, id) do
    resource
    |> Ash.read!(domain: Factory)
    |> Enum.find(&(&1.id == id))
  end

  defp get_by_id!(resource, id) do
    find_by_id(resource, id) ||
      raise ArgumentError, "#{inspect(resource)} #{id} was not found"
  end

  defp finalize_gate!(gate, run_spec, run_attempt, slice_result, opts) do
    case Keyword.get(opts, :finalize_gate) do
      fun when is_function(fun, 3) ->
        fun.(gate, run_spec, run_attempt)

      nil ->
        default_finalize_gate!(gate, run_spec, run_attempt, slice_result, opts)
    end
  end

  defp default_finalize_gate!(
         %Gate.Result{} = gate,
         run_spec,
         %RunAttempt{} = run_attempt,
         slice_result,
         opts
       ) do
    Finalizer.finalize!(
      gate,
      %{
        run_attempt: run_attempt,
        run_spec: run_spec,
        trust_evidence: trust_evidence(slice_result)
      },
      actor: Keyword.get(opts, :actor, "serial-driver")
    )
  end

  defp default_finalize_gate!(_gate, _run_spec, run_attempt, _slice_result, _opts) do
    %{run_attempt: run_attempt}
  end

  # ADR-23: thread the slice run's calibration/baseline signals into the gate
  # finalizer so a passed-but-unconfident run abstains. nil => no evidence =>
  # legacy auto-accept.
  defp trust_evidence(%{output: output}) when is_map(output),
    do: TrustEvidence.from_run_output(output)

  defp trust_evidence(_slice_result), do: nil

  defp advance_workspace_base!(run_spec, slice_key, finalization, opts) do
    case Keyword.get(opts, :advance_workspace_base) do
      fun when is_function(fun, 3) ->
        fun.(run_spec, slice_key, finalization)

      false ->
        :ok

      nil ->
        default_advance_workspace_base!(run_spec, slice_key)
    end
  end

  defp default_advance_workspace_base!(run_spec, slice_key) do
    case workspace_path(run_spec) do
      nil ->
        :ok

      workspace_path ->
        commit_workspace_changes!(workspace_path, slice_key)
    end
  end

  defp workspace_path(run_spec) do
    run_spec
    |> value(:station_plan, %{})
    |> list(:stations)
    |> Enum.find(&(value(&1, :key) == "implement"))
    |> value(:input, %{})
    |> value(:workspace_path)
  end

  defp commit_workspace_changes!(workspace_path, slice_key) do
    case git!(workspace_path, ["status", "--porcelain"]) do
      "" ->
        :ok

      _dirty ->
        git!(workspace_path, ["add", "-A"])

        git!(workspace_path, [
          "-c",
          "user.email=conveyor@example.invalid",
          "-c",
          "user.name=Conveyor Serial Driver",
          "commit",
          "-m",
          "conveyor: accept #{slice_key}"
        ])

        :ok
    end
  end

  defp topo_order(work_graph, selected_slice_ids) do
    selected = MapSet.new(selected_slice_ids)

    edges =
      work_graph
      |> list(:work_dependencies)
      |> Enum.filter(&(value(&1, :kind) in ["execution_hard", :execution_hard]))
      |> Enum.filter(&(value(&1, :from) in selected and value(&1, :to) in selected))

    do_topo(selected_slice_ids, edges, [])
  end

  defp do_topo([], _edges, done), do: Enum.reverse(done)

  defp do_topo(remaining, edges, done) do
    done_set = MapSet.new(done)

    case Enum.find(remaining, &ready?(&1, edges, done_set)) do
      nil ->
        raise ArgumentError, "selected slice dependency cycle: #{Enum.join(remaining, " -> ")}"

      slice_key ->
        do_topo(List.delete(remaining, slice_key), edges, [slice_key | done])
    end
  end

  defp ready?(slice_key, edges, done_set) do
    edges
    |> Enum.filter(&(value(&1, :to) == slice_key))
    |> Enum.all?(&(value(&1, :from) in done_set))
  end

  defp single_slice_graph!(work_graph, slice_key) do
    slice =
      work_graph
      |> list(:slices)
      |> Enum.find(&(value(&1, :stable_key) == slice_key or value(&1, :key) == slice_key)) ||
        raise ArgumentError, "slice #{slice_key} was not found in work_graph"

    work_graph
    |> stringify_keys()
    |> Map.put("slices", [stringify_keys(slice)])
    |> Map.put("work_dependencies", [])
  end

  defp slice_for!(slice_key, opts) do
    case Keyword.get(opts, :slices_by_stable_key, %{}) do
      %{^slice_key => slice} ->
        slice

      _missing ->
        raise ArgumentError, "SerialDriver needs :slices_by_stable_key for #{slice_key}"
    end
  end

  defp patch_ref_for(slice_key, opts) do
    cond do
      is_function(Keyword.get(opts, :patch_ref), 1) ->
        Keyword.fetch!(opts, :patch_ref).(slice_key)

      is_map(Keyword.get(opts, :patch_refs_by_slice)) ->
        Map.get(Keyword.fetch!(opts, :patch_refs_by_slice), slice_key)

      true ->
        Keyword.get(opts, :patch_ref)
    end
  end

  defp gate_passed?(gate), do: Map.get(gate, :passed?) || Map.get(gate, "passed?") || false

  defp accepted?(finalization), do: final_outcome(finalization) in [:accepted, "accepted"]

  defp final_outcome(finalization) do
    finalization
    |> value(:run_attempt)
    |> value(:outcome)
  end

  defp finding_categories(gate) do
    gate
    |> Map.get(:findings, Map.get(gate, "findings", []))
    |> Enum.map(&(value(&1, :category) || value(&1, :rule_key) || inspect(&1)))
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp list(map, key) do
    case value(map, key, []) do
      values when is_list(values) -> values
      nil -> []
      value -> [value]
    end
  end

  defp value(map, key, default \\ nil)

  defp value(map, key, default) when is_map(map),
    do: Map.get(map, key, Map.get(map, to_string(key), default))

  defp value(_map, _key, default), do: default

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), stringify_nested(value)} end)
  end

  defp stringify_nested(value) when is_map(value), do: stringify_keys(value)
  defp stringify_nested(value) when is_list(value), do: Enum.map(value, &stringify_nested/1)
  defp stringify_nested(value), do: value

  defp git!(workspace_path, args) do
    case System.cmd("git", ["-C", workspace_path | args], stderr_to_stdout: true) do
      {output, 0} -> String.trim(output)
      {output, status} -> raise "git #{Enum.join(args, " ")} failed (#{status}): #{output}"
    end
  end

  defp digest(label), do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, label), case: :lower)
end
