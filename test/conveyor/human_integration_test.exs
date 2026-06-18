defmodule Conveyor.HumanIntegrationTest do
  use Conveyor.DataCase, async: false

  import Conveyor.FactoryFixtures

  alias Conveyor.Factory
  alias Conveyor.Factory.HumanApproval
  alias Conveyor.HumanIntegration

  test "records an external commit as a human approval" do
    fixture = create_artifact_run!(blob_root: temp_dir!("human-integration"))

    approval =
      HumanIntegration.record!(
        run_attempt_id: fixture.run_attempt.id,
        actor: "human@example.test",
        external_commit: String.duplicate("a", 40),
        rationale: "Merged manually."
      )

    assert approval.decision == :recorded_external_action
    assert approval.external_commit == String.duplicate("a", 40)
    assert approval.equivalence_decision == :unknown
    assert approval.run_attempt_id == fixture.run_attempt.id
  end

  test "records an explicit not-integrated decision" do
    fixture = create_artifact_run!(blob_root: temp_dir!("human-not-integrated"))

    approval =
      HumanIntegration.record!(
        run_attempt_id: fixture.run_attempt.id,
        actor: "human@example.test",
        not_integrated: true,
        rationale: "Rejected after review."
      )

    assert approval.decision == :not_integrated
    assert is_nil(approval.external_commit)
  end

  test "requires either an external commit or not-integrated decision" do
    fixture = create_artifact_run!(blob_root: temp_dir!("human-invalid"))

    assert_raise ArgumentError, ~r/external commit or not_integrated/, fn ->
      HumanIntegration.record!(
        run_attempt_id: fixture.run_attempt.id,
        actor: "human@example.test"
      )
    end

    assert [] = Ash.read!(HumanApproval, domain: Factory)
  end
end
