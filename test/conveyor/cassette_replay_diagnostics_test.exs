defmodule Conveyor.CassetteReplayDiagnosticsTest do
  use ExUnit.Case, async: true

  alias Conveyor.Cassettes.ReplayDiagnostics

  @recorded %{
    tool_records: [
      %{
        "tool_call_id" => "tool-1",
        "tool_contract_key" => "shell.exec",
        "normalized_args" => %{"cmd" => "mix test"}
      }
    ],
    causal_events: [
      %{"event_id" => "agent:1", "happens_after" => []},
      %{"event_id" => "tool:1", "happens_after" => ["agent:1"]}
    ]
  }

  test "diagnoses different requested replayable tool" do
    diagnostics =
      ReplayDiagnostics.compare(@recorded, %{
        tool_records: [
          %{
            "tool_call_id" => "tool-1",
            "tool_contract_key" => "fs.write",
            "normalized_args" => %{"path" => "README.md"}
          }
        ],
        causal_events: @recorded.causal_events
      })

    assert [%{rule_key: "strict_replay.tool_contract_changed"} = finding] = diagnostics
    assert finding.anchor == "tool-1"
    assert finding.severity == :blocking
  end

  test "diagnoses different normalized args" do
    diagnostics =
      ReplayDiagnostics.compare(@recorded, %{
        tool_records: [
          %{
            "tool_call_id" => "tool-1",
            "tool_contract_key" => "shell.exec",
            "normalized_args" => %{"cmd" => "mix format"}
          }
        ],
        causal_events: @recorded.causal_events
      })

    assert [%{rule_key: "strict_replay.normalized_args_changed"} = finding] = diagnostics
    assert finding.anchor == "tool-1"
  end

  test "diagnoses causal sequence divergence" do
    diagnostics =
      ReplayDiagnostics.compare(@recorded, %{
        tool_records: @recorded.tool_records,
        causal_events: [
          %{"event_id" => "tool:1", "happens_after" => []},
          %{"event_id" => "agent:1", "happens_after" => []}
        ]
      })

    assert [%{rule_key: "strict_replay.causal_sequence_changed"} = finding] = diagnostics
    assert finding.anchor == "causal_events"
  end

  test "identical strict replay material has no diagnostics" do
    assert ReplayDiagnostics.compare(@recorded, @recorded) == []
  end
end
