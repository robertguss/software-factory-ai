defmodule Conveyor.PhaseNextDecisionSchemaTest do
  use ExUnit.Case, async: true

  @schema_path Path.expand("../../docs/schemas/conveyor.phase_next_decision@1.json", __DIR__)
  @valid_example Path.expand(
                   "../../docs/schemas/examples/conveyor.phase_next_decision.valid.json",
                   __DIR__
                 )
  @invalid_missing_branch Path.expand(
                            "../../docs/schemas/examples/conveyor.phase_next_decision.invalid.missing-selected-branches.json",
                            __DIR__
                          )

  test "valid PhaseNextDecision example conforms to the public schema" do
    assert {:ok, _validated} =
             @valid_example
             |> read_json!()
             |> JSV.validate(schema_root!())
  end

  test "PhaseNextDecision requires selected branches" do
    assert {:error, _error} =
             @invalid_missing_branch
             |> read_json!()
             |> JSV.validate(schema_root!())
  end

  defp schema_root! do
    @schema_path
    |> read_json!()
    |> JSV.build!()
  end

  defp read_json!(path), do: path |> File.read!() |> Jason.decode!()
end
