defmodule Conveyor.Planning.PlanFoundry.CodexDrafterTest do
  @moduledoc "ADR-27 — CodexDrafter prompt/parse logic + injectable completion seam (pure)."
  use ExUnit.Case, async: true

  alias Conveyor.Planning.PlanFoundry.CodexDrafter

  @plan_json ~s({"schema_version":"conveyor.plan@1","goal":"List ready issues."})

  describe "build_prompt/1" do
    test "is versioned and embeds the intent + the contract shape" do
      prompt = CodexDrafter.build_prompt("a CLI over issues.jsonl")

      assert prompt =~ "plan-drafter@1"
      assert prompt =~ "a CLI over issues.jsonl"
      assert prompt =~ "conveyor.plan@1"
      assert prompt =~ "REQ-001"
    end
  end

  describe "parse_plan/1" do
    test "parses raw JSON into a map" do
      assert {:ok, %{"schema_version" => "conveyor.plan@1"}} = CodexDrafter.parse_plan(@plan_json)
    end

    test "parses a ```json-fenced response" do
      fenced = "Sure!\n```json\n#{@plan_json}\n```\n"
      assert {:ok, %{"goal" => "List ready issues."}} = CodexDrafter.parse_plan(fenced)
    end

    test "rejects non-map JSON" do
      assert CodexDrafter.parse_plan("[1,2,3]") == {:error, :plan_not_a_map}
    end

    test "rejects non-JSON" do
      assert CodexDrafter.parse_plan("not json at all") == {:error, :invalid_plan_json}
    end
  end

  describe "draft_plan/2 via injected completion" do
    test "returns the parsed plan when the agent emits valid JSON" do
      completion = fn _prompt, _opts -> {:ok, @plan_json} end

      assert {:ok, %{"schema_version" => "conveyor.plan@1"}} =
               CodexDrafter.draft_plan("intent", completion: completion)
    end

    test "surfaces a parse error for a bad response" do
      completion = fn _prompt, _opts -> {:ok, "garbage"} end

      assert CodexDrafter.draft_plan("intent", completion: completion) ==
               {:error, :invalid_plan_json}
    end

    test "propagates a completion error" do
      completion = fn _prompt, _opts -> {:error, :rate_limited} end
      assert CodexDrafter.draft_plan("intent", completion: completion) == {:error, :rate_limited}
    end

    test "default completion parses the codex JSONL final message" do
      jsonl =
        Jason.encode!(%{
          "type" => "item.completed",
          "item" => %{"type" => "agent_message", "text" => @plan_json}
        })

      exec = fn _prompt, _opts -> {jsonl <> "\n", 0} end

      assert {:ok, %{"schema_version" => "conveyor.plan@1"}} =
               CodexDrafter.draft_plan("intent", codex_exec: exec)
    end

    test "an empty codex response is an error" do
      exec = fn _prompt, _opts -> {"", 0} end

      assert CodexDrafter.draft_plan("intent", codex_exec: exec) ==
               {:error, :codex_empty_response}
    end

    @tag :live_agent
    test "live codex drafts a plan from intent" do
      assert {:ok, plan} =
               CodexDrafter.draft_plan(
                 "Build a tiny Python CLI that prints the number of lines in a file."
               )

      assert is_map(plan)
    end
  end
end
