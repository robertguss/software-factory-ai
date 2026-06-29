defmodule Conveyor.Planning.PlanFoundry.ClaudeCodeDrafterTest do
  @moduledoc "ADR-27/KTD7 — ClaudeCodeDrafter draft_plan/2 orchestration + guarded outer-envelope decode."
  use ExUnit.Case, async: true

  alias Conveyor.Planning.PlanFoundry.ClaudeCodeDrafter

  @plan_json ~s({"schema_version":"conveyor.plan@1","goal":"List ready issues."})

  describe "draft_plan/2 via injected completion" do
    test "returns the parsed plan when the agent emits valid JSON" do
      completion = fn _prompt, _opts -> {:ok, @plan_json} end

      assert {:ok, %{"schema_version" => "conveyor.plan@1"}} =
               ClaudeCodeDrafter.draft_plan("intent", completion: completion)
    end

    test "surfaces a parse error for non-JSON text" do
      completion = fn _prompt, _opts -> {:ok, "garbage"} end

      assert ClaudeCodeDrafter.draft_plan("intent", completion: completion) ==
               {:error, :invalid_plan_json}
    end

    test "surfaces a plan_not_a_map error for non-map JSON" do
      completion = fn _prompt, _opts -> {:ok, "[1, 2, 3]"} end

      assert ClaudeCodeDrafter.draft_plan("intent", completion: completion) ==
               {:error, :plan_not_a_map}
    end

    test "propagates a completion error" do
      completion = fn _prompt, _opts -> {:error, :rate_limited} end

      assert ClaudeCodeDrafter.draft_plan("intent", completion: completion) ==
               {:error, :rate_limited}
    end
  end

  describe "default_completion via injected claude_exec" do
    test "extracts and parses the .result field of the JSON envelope" do
      exec = fn _prompt, _opts -> {Jason.encode!(%{"result" => @plan_json}), 0} end

      assert {:ok, %{"schema_version" => "conveyor.plan@1"}} =
               ClaudeCodeDrafter.draft_plan("intent", claude_exec: exec)
    end

    test "an empty .result is an empty-response error" do
      exec = fn _prompt, _opts -> {Jason.encode!(%{"result" => "   "}), 0} end

      assert ClaudeCodeDrafter.draft_plan("intent", claude_exec: exec) ==
               {:error, :claude_empty_response}
    end

    test "non-JSON stdout with non-zero exit is a structured error, not a raise" do
      exec = fn _prompt, _opts -> {"not json", 1} end

      assert {:error, {:claude_exec_failed, "not json"}} =
               ClaudeCodeDrafter.draft_plan("intent", claude_exec: exec)
    end

    test "blank stdout with non-zero exit is a structured error, not a raise" do
      exec = fn _prompt, _opts -> {"", 1} end

      assert {:error, {:claude_exec_failed, ""}} =
               ClaudeCodeDrafter.draft_plan("intent", claude_exec: exec)
    end

    test "is_error: true envelope is a structured error" do
      envelope = Jason.encode!(%{"is_error" => true, "result" => "boom"})
      exec = fn _prompt, _opts -> {envelope, 0} end

      assert {:error, {:claude_exec_failed, %{"is_error" => true}}} =
               ClaudeCodeDrafter.draft_plan("intent", claude_exec: exec)
    end

    test "a JSON envelope missing .result is a structured error" do
      exec = fn _prompt, _opts -> {Jason.encode!(%{"subtype" => "success"}), 0} end

      assert {:error, {:claude_exec_failed, %{"subtype" => "success"}}} =
               ClaudeCodeDrafter.draft_plan("intent", claude_exec: exec)
    end
  end

  describe "model_args/1" do
    test "defaults the model to opus" do
      assert ClaudeCodeDrafter.model_args([]) == ["--model", "opus"]
    end

    test "honors an explicit claude_code_model" do
      assert ClaudeCodeDrafter.model_args(claude_code_model: "sonnet") ==
               ["--model", "sonnet"]
    end
  end

  describe "live agent" do
    @tag :live_agent
    test "real claude drafts a conveyor.plan@1 from an intent" do
      assert {:ok, plan} =
               ClaudeCodeDrafter.draft_plan(
                 "Build a tiny Python CLI that prints the number of lines in a file."
               )

      assert is_map(plan)
    end
  end
end
