defmodule Conveyor.GateTest do
  use ExUnit.Case, async: true

  alias Conveyor.Gate
  alias Conveyor.Jobs.RunGate

  defmodule PassStage do
    @behaviour Conveyor.Gate.Stage

    @impl true
    def run(_context, _opts) do
      %{status: :passed, evidence_refs: ["evidence.json"], input_digests: %{"input" => "abc"}}
    end
  end

  defmodule FailStage do
    @behaviour Conveyor.Gate.Stage

    @impl true
    def run(_context, _opts) do
      %{
        status: :failed,
        evidence_refs: ["gate/failure.json"],
        findings: [
          %{"category" => "test", "severity" => "blocking", "message" => "Required stage failed."}
        ]
      }
    end
  end

  defmodule RaiseStage do
    @behaviour Conveyor.Gate.Stage

    @impl true
    def run(_context, _opts), do: raise("stage exploded")
  end

  defmodule CanaryContextStage do
    @behaviour Conveyor.Gate.Stage

    @impl true
    def run(%{mode: :gate_only, patch_set: %{source: :canary}}, _opts), do: %{status: :passed}
    def run(_context, _opts), do: %{status: :failed}
  end

  test "composition runs all stages and fails when any required stage fails" do
    result =
      Gate.run!(context(), [
        %{key: "first", module: PassStage},
        %{key: "required_failure", module: FailStage},
        %{key: "still_runs", module: PassStage}
      ])

    refute result.passed?
    assert result.status == :failed
    assert Enum.map(result.stages, & &1.key) == ["first", "required_failure", "still_runs"]
    assert Enum.map(result.stages, & &1.status) == [:passed, :failed, :passed]
    assert [%{"category" => "test"}] = result.findings
  end

  test "advisory stage failure does not fail the gate" do
    result =
      Gate.run!(context(), [
        %{key: "required", module: PassStage},
        %{key: "advisory", module: FailStage, required?: false}
      ])

    assert result.passed?
    assert result.status == :passed
    assert Enum.find(result.stages, &(&1.key == "advisory")).status == :failed
  end

  test "stage exceptions fail closed and are recorded as blocking findings" do
    result =
      Gate.run!(context(), [
        %{key: "raises", module: RaiseStage}
      ])

    refute result.passed?
    assert [%{"category" => "gate_stage_exception", "stage" => "raises"}] = result.findings
  end

  test "gate result attrs include ordered stage maps and required digests" do
    result = Gate.run!(context(), [%{key: "required", module: PassStage}])

    assert result.gate_result_attrs.passed
    assert result.gate_result_attrs.run_attempt_id == "run-attempt-1"
    assert result.gate_result_attrs.gate_version == "gate@1"
    assert result.gate_result_attrs.gate_code_sha256 == "sha256:gate"
    assert [%{"key" => "required", "status" => "passed"}] = result.gate_result_attrs.stages
  end

  test "gate-only facade runs against injected canary patch context" do
    result =
      RunGate.run_gate_only!(
        Map.put(context(), :patch_set, %{source: :canary}),
        [%{key: "canary_context", module: CanaryContextStage}]
      )

    assert result.passed?
    assert [%{key: "canary_context", status: :passed}] = result.stages
  end

  defp context do
    %{
      run_attempt_id: "run-attempt-1",
      gate_code_sha256: "sha256:gate",
      policy_sha256: "sha256:policy",
      contract_lock_sha256: "sha256:contract"
    }
  end
end
