defmodule Conveyor.ContractForge.FalsifierForgeTest do
  # Pure pre-agent contract check: no DB, no workspace, no execution.
  use ExUnit.Case, async: true

  alias Conveyor.ContractForge.FalsifierForge

  describe "run!/2 red-on-base safety" do
    test "returns a passed report when every criterion has a red-on-base seed and required test" do
      criteria = [
        %{"id" => "AC-001", "required_test_refs" => ["test/foo_test.exs:Foo"]},
        %{"id" => "AC-002", "required_test_refs" => ["test/bar_test.exs:Bar"]}
      ]

      seeds = [
        %{"source_acceptance_criterion_id" => "AC-001", "seed_id" => "falsifier:AC-001:row:0"},
        %{"source_acceptance_criterion_id" => "AC-002", "seed_id" => "falsifier:AC-002:row:0"}
      ]

      report = FalsifierForge.run!(criteria, seeds)

      assert report["schema_version"] == "conveyor.falsifier_forge@1"
      assert report["status"] == "passed"
      assert report["phase"] == "pre_agent_contract_lock"
      assert report["red_on_base_count"] == 2

      assert [row1, row2] = report["acceptance_criteria"]

      assert row1["id"] == "AC-001"
      assert row1["expected_on_base"] == "fail"
      assert row1["required_test_refs"] == ["test/foo_test.exs:Foo"]
      assert row1["seed_ids"] == ["falsifier:AC-001:row:0"]

      assert row2["id"] == "AC-002"
      assert row2["seed_ids"] == ["falsifier:AC-002:row:0"]
    end

    test "raises when a criterion has required tests but no red-on-base seed" do
      criteria = [%{"id" => "AC-009", "required_test_refs" => ["test/foo_test.exs:Foo"]}]
      seeds = []

      assert_raise ArgumentError, ~r/missing red-on-base coverage for AC-009/, fn ->
        FalsifierForge.run!(criteria, seeds)
      end
    end

    test "raises when a criterion has a seed but no required test refs" do
      criteria = [%{"id" => "AC-010", "required_test_refs" => []}]

      seeds = [
        %{"source_acceptance_criterion_id" => "AC-010", "seed_id" => "falsifier:AC-010:row:0"}
      ]

      assert_raise ArgumentError, ~r/missing red-on-base coverage for AC-010/, fn ->
        FalsifierForge.run!(criteria, seeds)
      end
    end
  end
end
