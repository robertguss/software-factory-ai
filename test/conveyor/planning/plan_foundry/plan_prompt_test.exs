defmodule Conveyor.Planning.PlanFoundry.PlanPromptTest do
  @moduledoc "ADR-27 — shared plan-drafting prompt build/parse (pure)."
  use ExUnit.Case, async: true

  alias Conveyor.Planning.PlanFoundry.PlanPrompt

  @plan_json ~s({"schema_version":"conveyor.plan@1","goal":"List ready issues."})

  describe "build_prompt/1" do
    test "is versioned and embeds the intent + the contract shape" do
      prompt = PlanPrompt.build_prompt("a CLI over issues.jsonl")

      assert prompt =~ "plan-drafter@1"
      assert prompt =~ "a CLI over issues.jsonl"
      assert prompt =~ "conveyor.plan@1"
      assert prompt =~ "REQ-001"
      assert prompt =~ "^[A-Z]+-[0-9]{3}$"
    end
  end

  describe "parse_plan/1" do
    test "parses raw JSON into a map" do
      assert {:ok, %{"schema_version" => "conveyor.plan@1"}} = PlanPrompt.parse_plan(@plan_json)
    end

    test "parses a ```json-fenced response" do
      fenced = "Sure!\n```json\n#{@plan_json}\n```\n"
      assert {:ok, %{"goal" => "List ready issues."}} = PlanPrompt.parse_plan(fenced)
    end

    test "rejects non-map JSON" do
      assert PlanPrompt.parse_plan("[1,2,3]") == {:error, :plan_not_a_map}
    end

    test "rejects non-JSON" do
      assert PlanPrompt.parse_plan("not json at all") == {:error, :invalid_plan_json}
    end
  end
end
