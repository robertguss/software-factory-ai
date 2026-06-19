defmodule Conveyor.AgentRunner.MockDegraded do
  @moduledoc """
  Deterministic degraded adapter for adapter-qualification tests.

  It never calls a provider. Each scenario represents a capability mismatch or
  bad event stream that the conductor must classify predictably.
  """

  @behaviour Conveyor.AgentRunner

  alias Conveyor.AgentRunner.RawRunResult

  @adapter "mock_degraded"

  @cases [
    %{
      branch: :observe_only_pre_exec_policy,
      category: :capability_mismatch,
      expected: :degraded_ok,
      reason: "adapter can observe commands but cannot enforce pre-exec policy"
    },
    %{
      branch: :absent_cancellation,
      category: :capability_mismatch,
      expected: :fail_closed,
      reason: "adapter cannot acknowledge cancellation"
    },
    %{
      branch: :delayed_cancellation,
      category: :capability_mismatch,
      expected: :fail_closed,
      reason: "adapter cancellation acknowledgement exceeded the bound"
    },
    %{
      branch: :no_diff_capture,
      category: :capability_mismatch,
      expected: :degraded_ok,
      reason: "adapter cannot independently produce a patch set"
    },
    %{
      branch: :no_cost_reporting,
      category: :capability_mismatch,
      expected: :degraded_ok,
      reason: "adapter cannot report provider cost"
    },
    %{
      branch: :malformed_events,
      category: :event_integrity,
      expected: :fail_closed,
      reason: "adapter emitted malformed event payloads"
    },
    %{
      branch: :out_of_order_events,
      category: :event_integrity,
      expected: :fail_closed,
      reason: "adapter emitted non-monotonic event sequence numbers"
    },
    %{
      branch: :duplicate_events,
      category: :event_integrity,
      expected: :fail_closed,
      reason: "adapter emitted duplicate event ids"
    },
    %{
      branch: :partial_tool_result_capture,
      category: :capture_degraded,
      expected: :degraded_ok,
      reason: "adapter captured only part of a tool result"
    },
    %{
      branch: :timeout,
      category: :runtime_failure,
      expected: :fail_closed,
      reason: "adapter run exceeded its timeout"
    },
    %{
      branch: :disconnect,
      category: :runtime_failure,
      expected: :fail_closed,
      reason: "adapter stream disconnected before a terminal result"
    },
    %{
      branch: :capability_drift,
      category: :capability_drift,
      expected: :fail_closed,
      reason: "adapter behaviour no longer matches probed capabilities"
    }
  ]

  @impl true
  def capabilities do
    %{
      streaming_events: true,
      pre_exec_command_policy: false,
      cancellation: :none,
      diff_capture: :adapter_reported,
      cost_reporting: :none,
      mcp_support: false,
      slash_commands_enabled: false,
      structured_output: true,
      session_resume: false,
      known_limitations: []
    }
  end

  @spec qualification_cases() :: [map()]
  def qualification_cases, do: @cases

  @impl true
  def run(_run_prompt, _workspace, _policy, opts \\ []) do
    branch = Keyword.get(opts, :scenario, :observe_only_pre_exec_policy)
    case_entry = case_entry!(branch)

    case case_entry.expected do
      :fail_closed -> {:error, finding(case_entry)}
      :degraded_ok -> {:ok, result(case_entry, opts)}
    end
  end

  @impl true
  def cancel(_session_id), do: {:error, finding(case_entry!(:absent_cancellation))}

  defp result(%{branch: :partial_tool_result_capture} = case_entry, opts) do
    %RawRunResult{
      summary: "Mock degraded adapter captured partial tool results",
      messages: [%{"role" => "assistant", "content" => "partial tool result captured"}],
      tool_calls: [%{"name" => "shell", "capture" => "partial"}],
      attempted_commands: ["mock degraded command"],
      metadata: metadata(case_entry, opts)
    }
  end

  defp result(case_entry, opts) do
    %RawRunResult{
      summary: "Mock degraded adapter completed #{case_entry.branch}",
      metadata: metadata(case_entry, opts)
    }
  end

  defp metadata(case_entry, opts) do
    %{
      "adapter" => @adapter,
      "session_id" => Keyword.get(opts, :session_id, "mock-degraded"),
      "qualification_branch" => Atom.to_string(case_entry.branch),
      "qualification_category" => Atom.to_string(case_entry.category),
      "degraded" => true,
      "reason" => case_entry.reason
    }
  end

  defp finding(case_entry) do
    %{
      "severity" => "blocking",
      "category" => "adapter_conformance_failure",
      "branch" => Atom.to_string(case_entry.branch),
      "qualification_category" => Atom.to_string(case_entry.category),
      "reason" => case_entry.reason,
      "fail_closed" => true
    }
  end

  defp case_entry!(branch) do
    Enum.find(@cases, &(&1.branch == branch)) ||
      raise ArgumentError, "unknown MockDegraded scenario #{inspect(branch)}"
  end
end
