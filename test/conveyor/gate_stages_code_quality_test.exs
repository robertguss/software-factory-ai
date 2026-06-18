defmodule Conveyor.GateStagesCodeQualityTest do
  use ExUnit.Case, async: true

  alias Conveyor.Factory.CodeQualityRun
  alias Conveyor.Gate.Stages.CodeQualityDelta

  test "gate-blocking deterministic adapter fails on new high-risk findings" do
    result =
      CodeQualityDelta.run(%{
        code_quality_run: quality_run(new_high_risk_findings: 1),
        code_quality_result: quality_result(),
        gate_blocking_quality_adapters: ["CodeQualityAdapter.CodeScent"]
      })

    assert result.status == :failed
    assert result.input_digests["gate_blocking_selected"] == true
    assert result.input_digests["deterministic_contract"] == true

    assert [%{"category" => "new_high_risk_findings", "severity" => "blocking"}] =
             result.findings
  end

  test "advisory adapters never block on high-risk findings" do
    result =
      CodeQualityDelta.run(%{
        code_quality_run:
          quality_run(
            adapter: "CodeQualityAdapter.LocalPython",
            new_high_risk_findings: 3
          ),
        code_quality_result:
          quality_result(
            metadata: %{
              "adapter_contract" => %{
                "deterministic_output" => true,
                "result_schema" => "conveyor.quality_result@1",
                "fixture_suite" => "quality_adapter_conformance",
                "threshold_policy" => %{"new_high_risk_findings" => 0},
                "advisory_only" => true
              }
            }
          )
      })

    assert result.status == :passed

    assert [%{"category" => "new_high_risk_findings", "severity" => "warning"}] =
             result.findings
  end

  test "selected adapter must declare deterministic gate-blocking contract" do
    result =
      CodeQualityDelta.run(%{
        code_quality_run: quality_run(new_high_risk_findings: 0),
        code_quality_result:
          quality_result(
            metadata: %{
              "adapter_contract" => %{
                "deterministic_output" => true,
                "result_schema" => "conveyor.quality_result@1",
                "threshold_policy" => %{"new_high_risk_findings" => 0},
                "advisory_only" => true
              }
            }
          ),
        code_quality_gate_blocking: true
      })

    assert result.status == :failed

    assert [
             %{
               "category" => "quality_adapter_contract_not_gate_blocking",
               "severity" => "blocking"
             }
           ] = result.findings
  end

  test "configured threshold is respected for gate-blocking adapters" do
    result =
      CodeQualityDelta.run(%{
        code_quality_run: quality_run(new_high_risk_findings: 1),
        code_quality_result: quality_result(),
        code_quality_gate_blocking: true,
        code_quality_policy: %{new_high_risk_findings_threshold: 2}
      })

    assert result.status == :passed
    assert result.findings == []
    assert result.input_digests["new_high_risk_findings_threshold"] == 2
  end

  test "selected gate-blocking adapter fails closed without a run" do
    result =
      CodeQualityDelta.run(%{
        code_quality_gate_blocking: true,
        code_quality_adapter_contract: gate_blocking_contract()
      })

    assert result.status == :failed

    assert [%{"category" => "missing_code_quality_run", "severity" => "blocking"}] =
             result.findings
  end

  defp quality_run(attrs) do
    struct!(
      CodeQualityRun,
      Keyword.merge(
        [
          adapter: "CodeQualityAdapter.CodeScent",
          profile: "standard",
          baseline_ref: "codescent/before.json",
          result_ref: "codescent/after.json",
          findings_summary: %{},
          new_high_risk_findings: 0,
          status: :succeeded
        ],
        attrs
      )
    )
  end

  defp quality_result(attrs \\ []) do
    Map.merge(
      %{
        "adapter" => "CodeQualityAdapter.CodeScent",
        "profile" => "standard",
        "status" => "succeeded",
        "new_high_risk_findings" => 0,
        "metadata" => %{"adapter_contract" => gate_blocking_contract()}
      },
      Map.new(attrs)
    )
  end

  defp gate_blocking_contract do
    %{
      "deterministic_output" => true,
      "result_schema" => "conveyor.quality_result@1",
      "fixture_suite" => "codescent_adapter_conformance",
      "threshold_policy" => %{"new_high_risk_findings" => 0},
      "gate_blocking_when_selected" => true,
      "advisory_only" => false
    }
  end
end
