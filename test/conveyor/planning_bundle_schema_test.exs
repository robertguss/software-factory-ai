defmodule Conveyor.PlanningBundleSchemaTest do
  use ExUnit.Case, async: true

  @schema_path Path.expand("../../docs/schemas/conveyor.planning_bundle@1.json", __DIR__)
  @valid_example Path.expand(
                   "../../docs/schemas/examples/conveyor.planning_bundle@1.valid.json",
                   __DIR__
                 )
  @invalid_missing_exclusion Path.expand(
                               "../../docs/schemas/examples/conveyor.planning_bundle@1.invalid.missing-approval-signature-exclusion.json",
                               __DIR__
                             )

  test "valid PlanningBundle example conforms to the public schema" do
    assert {:ok, _validated} =
             @valid_example
             |> read_json!()
             |> JSV.validate(schema_root!())
  end

  test "PlanningBundle requires explicit approval signature exclusion" do
    assert {:error, _error} =
             @invalid_missing_exclusion
             |> read_json!()
             |> JSV.validate(schema_root!())
  end

  test "schema registry declares PlanningBundle as current P2-B4 resource" do
    registry = read_json!("docs/schemas/registry.json")

    assert %{
             "schema_version" => "conveyor.planning_bundle@1",
             "file" => "conveyor.planning_bundle@1.json",
             "owner" => "P2-B4",
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
