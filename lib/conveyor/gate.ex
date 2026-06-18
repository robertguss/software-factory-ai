defmodule Conveyor.Gate do
  @moduledoc """
  Deterministic gate stage composition.

  Concrete stages implement `Conveyor.Gate.Stage` and receive a plain context
  map, allowing the same gate path to run against real implementer output or an
  injected canary fixture.
  """

  defmodule StageSpec do
    @moduledoc false

    @type t :: %__MODULE__{
            key: String.t(),
            module: module(),
            required?: boolean(),
            opts: keyword()
          }

    @enforce_keys [:key, :module]
    defstruct [:key, :module, required?: true, opts: []]
  end

  defmodule StageResult do
    @moduledoc false

    @type status :: :passed | :failed | :skipped
    @type t :: %__MODULE__{
            key: String.t(),
            status: status(),
            required?: boolean(),
            findings: [map()],
            evidence_refs: [String.t()],
            input_digests: map(),
            output_digest: String.t() | nil,
            duration_ms: non_neg_integer()
          }

    @enforce_keys [:key, :status, :required?]
    defstruct [
      :key,
      :status,
      :required?,
      :output_digest,
      findings: [],
      evidence_refs: [],
      input_digests: %{},
      duration_ms: 0
    ]
  end

  defmodule Result do
    @moduledoc false

    @type t :: %__MODULE__{
            status: :passed | :failed,
            passed?: boolean(),
            stages: [StageResult.t()],
            findings: [map()],
            gate_result_attrs: map()
          }

    @enforce_keys [:status, :passed?, :stages, :findings, :gate_result_attrs]
    defstruct [:status, :passed?, :stages, :findings, :gate_result_attrs]
  end

  @spec run!(map(), [StageSpec.t() | module() | map()], keyword()) :: Result.t()
  def run!(context, stage_specs, opts \\ []) when is_map(context) and is_list(stage_specs) do
    stages = Enum.map(stage_specs, &normalize_stage_spec!/1)
    stage_results = Enum.map(stages, &run_stage(&1, context))
    passed? = Enum.all?(stage_results, &stage_passes_gate?/1)
    status = if passed?, do: :passed, else: :failed
    findings = Enum.flat_map(stage_results, & &1.findings)

    result = %Result{
      status: status,
      passed?: passed?,
      stages: stage_results,
      findings: findings,
      gate_result_attrs: %{}
    }

    %{result | gate_result_attrs: gate_result_attrs(result, context, opts)}
  end

  @spec gate_result_attrs(Result.t(), map(), keyword()) :: map()
  def gate_result_attrs(%Result{} = result, context, opts \\ []) do
    %{
      run_attempt_id: value(context, :run_attempt_id),
      passed: result.passed?,
      stages: Enum.map(result.stages, &stage_result_map/1),
      false_negative: Keyword.get(opts, :false_negative),
      gate_version: Keyword.get(opts, :gate_version, "gate@1"),
      gate_code_sha256: required_digest!(context, opts, :gate_code_sha256),
      policy_sha256: required_digest!(context, opts, :policy_sha256),
      contract_lock_sha256: required_digest!(context, opts, :contract_lock_sha256),
      canary_suite_version: Keyword.get(opts, :canary_suite_version, "canary@1")
    }
  end

  defp normalize_stage_spec!(%StageSpec{} = spec), do: spec

  defp normalize_stage_spec!(module) when is_atom(module) do
    %StageSpec{key: module |> Module.split() |> List.last() |> Macro.underscore(), module: module}
  end

  defp normalize_stage_spec!(spec) when is_map(spec) do
    %StageSpec{
      key: to_string(Map.fetch!(spec, :key)),
      module: Map.fetch!(spec, :module),
      required?: Map.get(spec, :required?, true),
      opts: Map.get(spec, :opts, [])
    }
  end

  defp run_stage(%StageSpec{} = spec, context) do
    started = System.monotonic_time(:millisecond)

    try do
      spec.module.run(context, spec.opts)
      |> normalize_stage_result!(spec)
      |> Map.put(:duration_ms, elapsed_ms(started))
    rescue
      error ->
        %StageResult{
          key: spec.key,
          status: :failed,
          required?: spec.required?,
          duration_ms: elapsed_ms(started),
          findings: [
            %{
              "category" => "gate_stage_exception",
              "severity" => "blocking",
              "stage" => spec.key,
              "message" => Exception.message(error)
            }
          ]
        }
    end
  end

  defp normalize_stage_result!(%StageResult{} = result, %StageSpec{} = spec) do
    %{result | key: spec.key, required?: spec.required?}
  end

  defp normalize_stage_result!(result, %StageSpec{} = spec) when is_map(result) do
    %StageResult{
      key: spec.key,
      status: Map.get(result, :status, Map.get(result, "status", :failed)),
      required?: spec.required?,
      findings: Map.get(result, :findings, Map.get(result, "findings", [])),
      evidence_refs: Map.get(result, :evidence_refs, Map.get(result, "evidence_refs", [])),
      input_digests: Map.get(result, :input_digests, Map.get(result, "input_digests", %{})),
      output_digest: Map.get(result, :output_digest, Map.get(result, "output_digest"))
    }
  end

  defp stage_passes_gate?(%StageResult{required?: false}), do: true
  defp stage_passes_gate?(%StageResult{status: :passed}), do: true
  defp stage_passes_gate?(_stage), do: false

  defp stage_result_map(%StageResult{} = stage) do
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

  defp required_digest!(context, opts, key) do
    Keyword.get(opts, key) || value(context, key) ||
      raise ArgumentError, "#{key} is required to assemble GateResult attributes"
  end

  defp value(context, key), do: Map.get(context, key) || Map.get(context, Atom.to_string(key))
  defp elapsed_ms(started), do: max(System.monotonic_time(:millisecond) - started, 0)
end

defmodule Conveyor.Gate.Stage do
  @moduledoc """
  Behaviour for a deterministic gate stage.
  """

  @callback run(map(), keyword()) :: Conveyor.Gate.StageResult.t() | map()
end
