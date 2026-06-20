defmodule Conveyor.Planning.SerialDriver do
  @moduledoc """
  Width-1 driver for executing a frozen pilot selection serially.
  """

  alias Conveyor.Factory
  alias Conveyor.Factory.RunAttempt
  alias Conveyor.Gate
  alias Conveyor.Gate.Finalizer
  alias Conveyor.Jobs.RunGate
  alias Conveyor.Planning.PilotExecution
  alias Conveyor.Planning.RunSpecAssembler
  alias Conveyor.RunSlice

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

    %Result{status: status, order: order, events: events, report: report}
  end

  defp run_one!(slice_key, work_graph, sequence, opts) do
    single_slice_graph = single_slice_graph!(work_graph, slice_key)
    run_spec = assemble_run_spec!(slice_key, single_slice_graph, opts)
    run_attempt = create_run_attempt!(run_spec, opts)
    slice_result = run_slice!(run_attempt, opts)
    gate = run_gate!(run_spec, run_attempt, slice_result, opts)
    finalization = finalize_gate!(gate, run_spec, run_attempt, opts)
    passed? = slice_result.status == :succeeded and gate_passed?(gate) and accepted?(finalization)

    %{
      "slice_id" => slice_key,
      "sequence" => sequence,
      "status" => if(passed?, do: "passed", else: "parked"),
      "gate_result" => if(passed?, do: "first_pass", else: "eventual_pending"),
      "run_attempt_outcome" => final_outcome(finalization),
      "findings" => finding_categories(gate)
    }
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
        RunGate.run_gate_only!(
          %{
            run_attempt_id: run_attempt.id,
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

  defp finalize_gate!(gate, run_spec, run_attempt, opts) do
    case Keyword.get(opts, :finalize_gate) do
      fun when is_function(fun, 3) ->
        fun.(gate, run_spec, run_attempt)

      nil ->
        default_finalize_gate!(gate, run_spec, run_attempt, opts)
    end
  end

  defp default_finalize_gate!(%Gate.Result{} = gate, run_spec, %RunAttempt{} = run_attempt, opts) do
    Finalizer.finalize!(
      gate,
      %{run_attempt: run_attempt, run_spec: run_spec},
      actor: Keyword.get(opts, :actor, "serial-driver")
    )
  end

  defp default_finalize_gate!(_gate, _run_spec, run_attempt, _opts) do
    %{run_attempt: run_attempt}
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

  defp digest(label), do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, label), case: :lower)
end
