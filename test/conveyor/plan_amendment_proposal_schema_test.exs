defmodule Conveyor.PlanAmendmentProposalSchemaTest do
  use ExUnit.Case, async: true

  @schema_path Path.expand("../../docs/schemas/conveyor.plan_amendment_proposal@1.json", __DIR__)
  @valid_example Path.expand(
                   "../../docs/schemas/examples/conveyor.plan_amendment_proposal@1.valid.json",
                   __DIR__
                 )
  @invalid_missing_materiality Path.expand(
                                 "../../docs/schemas/examples/conveyor.plan_amendment_proposal@1.invalid.missing-materiality.json",
                                 __DIR__
                               )

  test "valid PlanAmendmentProposal example conforms to the public schema" do
    assert {:ok, _validated} =
             @valid_example
             |> read_json!()
             |> JSV.validate(schema_root!())
  end

  test "PlanAmendmentProposal requires materiality" do
    assert {:error, _error} =
             @invalid_missing_materiality
             |> read_json!()
             |> JSV.validate(schema_root!())
  end

  test "schema registry declares PlanAmendmentProposal as current P2-B6 resource" do
    registry = read_json!("docs/schemas/registry.json")

    assert %{
             "schema_version" => "conveyor.plan_amendment_proposal@1",
             "file" => "conveyor.plan_amendment_proposal@1.json",
             "owner" => "P2-B6",
             "writer_status" => "current"
           } in registry["schemas"]
  end

  defp schema_root! do
    @schema_path
    |> read_json!()
    |> JSV.build!()
  end

  defp read_json!(path), do: path |> File.read!() |> Jason.decode!()
end
