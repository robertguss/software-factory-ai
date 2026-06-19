defmodule Conveyor.ApprovalSetSchemaTest do
  use ExUnit.Case, async: true

  @schema_path Path.expand("../../docs/schemas/conveyor.approval_set@1.json", __DIR__)
  @valid_example Path.expand(
                   "../../docs/schemas/examples/conveyor.approval_set@1.valid.json",
                   __DIR__
                 )
  @invalid_missing_threshold Path.expand(
                               "../../docs/schemas/examples/conveyor.approval_set@1.invalid.missing-threshold-satisfied.json",
                               __DIR__
                             )

  test "valid ApprovalSet example conforms to the public schema" do
    assert {:ok, _validated} =
             @valid_example
             |> read_json!()
             |> JSV.validate(schema_root!())
  end

  test "ApprovalSet requires threshold satisfaction" do
    assert {:error, _error} =
             @invalid_missing_threshold
             |> read_json!()
             |> JSV.validate(schema_root!())
  end

  test "schema registry declares ApprovalSet as current P2-B5 resource" do
    registry = read_json!("docs/schemas/registry.json")

    assert %{
             "schema_version" => "conveyor.approval_set@1",
             "file" => "conveyor.approval_set@1.json",
             "owner" => "P2-B5",
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
