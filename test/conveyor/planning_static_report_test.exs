defmodule Conveyor.PlanningStaticReportTest do
  use ExUnit.Case, async: true

  alias Conveyor.Planning.StaticReport

  test "emits deterministic headless report from canonical findings" do
    package = %{
      artifact_digest: digest("package"),
      artifacts: %{work_graph: %{}, structural_dry_run: %{}},
      authority_effect: :none
    }

    findings = [
      %{rule_key: "traceability_gap", severity: :blocking, subject_key: "SLC-A"},
      %{rule_key: "oracle_infeasible", severity: :warning, subject_key: "SLC-B"}
    ]

    json = StaticReport.render(package, findings, format: :json)
    human = StaticReport.render(package, findings, format: :human)

    assert json.schema_version == "conveyor.static_compiler_report@1"
    assert json.status == :blocked
    assert json.finding_keys == ["traceability_gap", "oracle_infeasible"]
    assert json.package_digest == package.artifact_digest
    assert json.authority_effect == :none
    assert json.report_digest =~ ~r/^sha256:[0-9a-f]{64}$/

    assert human.status == :blocked
    assert human.finding_keys == json.finding_keys
    assert human.body =~ "traceability_gap"
    assert human.body =~ "oracle_infeasible"
    assert human.body_sha256 =~ ~r/^sha256:[0-9a-f]{64}$/
  end

  defp digest(label), do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, label), case: :lower)
end
