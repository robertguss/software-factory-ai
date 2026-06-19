defmodule Conveyor.PilotSelectionSchemaTest do
  use ExUnit.Case, async: true

  @schema_path Path.expand("../../docs/schemas/conveyor.pilot_selection@1.json", __DIR__)
  @valid_example Path.expand(
                   "../../docs/schemas/examples/conveyor.pilot_selection@1.valid.json",
                   __DIR__
                 )
  @invalid_missing_digest Path.expand(
                            "../../docs/schemas/examples/conveyor.pilot_selection@1.invalid.missing-selection-digest.json",
                            __DIR__
                          )

  test "valid PilotSelection example conforms to the public schema" do
    assert {:ok, _validated} =
             @valid_example
             |> read_json!()
             |> JSV.validate(schema_root!())
  end

  test "PilotSelection requires immutable selection digest" do
    assert {:error, _error} =
             @invalid_missing_digest
             |> read_json!()
             |> JSV.validate(schema_root!())
  end

  test "schema registry declares PilotSelection as current P2-B7 resource" do
    registry = read_json!("docs/schemas/registry.json")

    assert %{
             "schema_version" => "conveyor.pilot_selection@1",
             "file" => "conveyor.pilot_selection@1.json",
             "owner" => "P2-B7",
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
