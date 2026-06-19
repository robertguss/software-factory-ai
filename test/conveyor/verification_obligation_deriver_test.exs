defmodule Conveyor.VerificationObligationDeriverTest do
  use ExUnit.Case, async: true

  alias Conveyor.ContractForge.VerificationObligationDeriver

  test "derives deterministic VerificationObligations for acceptance criteria" do
    assert {:ok, obligations} =
             VerificationObligationDeriver.derive(%{
               "slice_id" => "SLC-001",
               "acceptance_criteria" => [
                 %{
                   "id" => "AC-001",
                   "machine_checkable" => true,
                   "verification_stage" => "unit",
                   "falsifying_conditions" => ["completed task is listed without completed=true"],
                   "required_test_refs" => ["test/tasks_test.exs::completion"]
                 }
               ]
             })

    assert [
             %{
               "schema_version" => "conveyor.verification_obligation@1",
               "slice_id" => "SLC-001",
               "acceptance_ref" => "AC-001",
               "obligation_kind" => "unit",
               "required" => true,
               "evidence_requirement_ref" => "test/tasks_test.exs::completion",
               "status" => "pending"
             }
           ] = obligations
  end

  test "blocks machine-checkable acceptance criteria without falsifying conditions" do
    assert {:error, findings} =
             VerificationObligationDeriver.derive(%{
               "slice_id" => "SLC-001",
               "acceptance_criteria" => [
                 %{
                   "id" => "AC-001",
                   "machine_checkable" => true,
                   "verification_stage" => "unit",
                   "falsifying_conditions" => []
                 }
               ]
             })

    assert Enum.map(findings, & &1.rule_key) == ["acceptance_criterion_missing_falsifier"]
  end
end
