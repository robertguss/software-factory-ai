defmodule Conveyor.CassetteCausalTranscriptTest do
  use ExUnit.Case, async: true

  alias Conveyor.Cassettes.CausalTranscript

  test "normalizes per-stream sequences and happens-before edges without hidden reasoning" do
    events =
      CausalTranscript.normalize_events([
        %{
          stream: "agent",
          event_type: "message_delta",
          payload: %{
            "text" => "working",
            "hidden_chain_of_thought" => "do not store"
          }
        },
        %{
          stream: "tool",
          event_type: "command_started",
          happens_after: ["agent:1"],
          payload: %{"argv" => ["mix", "test"]}
        },
        %{
          stream: "agent",
          event_type: "message_completed",
          payload: %{"content" => "done", "reasoning" => "private"}
        }
      ])

    assert Enum.map(events, & &1["event_id"]) == ["agent:1", "tool:1", "agent:2"]
    assert Enum.map(events, & &1["stream_sequence_no"]) == [1, 1, 2]
    assert Enum.at(events, 1)["happens_after"] == ["agent:1"]
    refute get_in(Enum.at(events, 0), ["payload", "hidden_chain_of_thought"])
    refute get_in(Enum.at(events, 2), ["payload", "reasoning"])
  end

  test "tool records normalize args, policy decision, result/error, idempotency, receipt, and causal linkage" do
    first =
      CausalTranscript.tool_record!(%{
        tool_contract_key: "shell.exec",
        tool_call_id: "tool-1",
        normalized_args: %{"cmd" => "mix test", "cwd" => "."},
        policy_decision: %{"decision" => "allow", "policy_ref" => "policy://1"},
        result: %{"exit_code" => 0, "stdout" => "ok"},
        effect_receipt_ref: "effect://receipt-1",
        caused_by: "agent:1"
      })

    reordered =
      CausalTranscript.tool_record!(%{
        tool_contract_key: "shell.exec",
        tool_call_id: "tool-1",
        normalized_args: %{"cwd" => ".", "cmd" => "mix test"},
        policy_decision: %{"policy_ref" => "policy://1", "decision" => "allow"},
        result: %{"stdout" => "ok", "exit_code" => 0},
        effect_receipt_ref: "effect://receipt-1",
        caused_by: "agent:1"
      })

    assert first["schema_version"] == "conveyor.tool_record@1"
    assert first["tool_contract_key"] == "shell.exec"
    assert first["policy_decision"]["decision"] == "allow"
    assert first["effect_receipt_ref"] == "effect://receipt-1"
    assert first["caused_by"] == "agent:1"
    assert first["idempotency_key"] == reordered["idempotency_key"]
  end

  test "tool records can capture errors but not hidden chain-of-thought fields" do
    record =
      CausalTranscript.tool_record!(%{
        tool_contract_key: "shell.exec",
        tool_call_id: "tool-2",
        normalized_args: %{"cmd" => "mix test"},
        policy_decision: %{"decision" => "allow"},
        error: %{"message" => "failed", "chain_of_thought" => "private"},
        caused_by: "agent:2"
      })

    assert record["error"] == %{"message" => "failed"}
    assert record["result"] == nil
  end
end
