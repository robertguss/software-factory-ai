defmodule Conveyor.SwarmReadinessAuditTest do
  use Conveyor.DataCase, async: false

  import Conveyor.FactoryFixtures

  alias Conveyor.Factory
  alias Conveyor.Factory.RunAttempt
  alias Conveyor.SwarmReadinessAudit

  test "audits every section 27 swarm-readiness field for a projected run" do
    fixture = create_artifact_run!(blob_root: temp_dir!("swarm-readiness"))

    Ash.update!(
      fixture.run_attempt,
      %{
        status: :reported,
        started_at: ~U[2026-06-18 01:00:00.000000Z],
        completed_at: ~U[2026-06-18 01:05:00.000000Z],
        head_tree_sha256: "sha256:" <> String.duplicate("1", 64)
      },
      domain: Factory
    )

    run_attempt =
      RunAttempt
      |> Ash.read!(domain: Factory)
      |> Enum.find(&(&1.id == fixture.run_attempt.id))

    audit = SwarmReadinessAudit.audit!(run_attempt)
    fields = audit["fields"]

    assert audit["schema_version"] == "conveyor.swarm_readiness_audit@1"
    assert audit["passed"] == true
    assert Enum.map(fields, & &1["field"]) == SwarmReadinessAudit.field_names()
    assert Enum.all?(fields, & &1["captured"])
    assert field!(fields, "likely_files")["source"] == "slice.likely_files"
    assert field!(fields, "trace_id")["value_summary"] == "trace-replay"
    assert field!(fields, "cost_tokens")["quality"] == "measured"
    assert field!(fields, "dependency_cache_hit_miss")["quality"] == "phase1_placeholder"
  end

  defp field!(fields, name) do
    Enum.find(fields, &(&1["field"] == name)) || raise "missing field #{name}"
  end
end
