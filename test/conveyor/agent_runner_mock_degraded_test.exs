defmodule Conveyor.AgentRunnerMockDegradedTest do
  use ExUnit.Case, async: true

  alias Conveyor.AgentRunner
  alias Conveyor.AgentRunner.Capabilities
  alias Conveyor.AgentRunner.MockDegraded
  alias Conveyor.AgentRunner.RawRunResult

  @branches [
    :observe_only_pre_exec_policy,
    :absent_cancellation,
    :delayed_cancellation,
    :no_diff_capture,
    :no_cost_reporting,
    :malformed_events,
    :out_of_order_events,
    :duplicate_events,
    :partial_tool_result_capture,
    :timeout,
    :disconnect,
    :capability_drift
  ]

  test "declares degraded capabilities capped by the shared capability rules" do
    capabilities = Capabilities.new!(MockDegraded.capabilities())

    refute capabilities.pre_exec_command_policy
    assert capabilities.cancellation == :none
    assert capabilities.diff_capture == :adapter_reported
    assert capabilities.cost_reporting == :none
    assert Capabilities.autonomy_ceiling(capabilities) == "L1"
    assert :no_pre_exec_interception in capabilities.known_limitations
    assert :adapter_reported_diff_only in capabilities.known_limitations
    assert :provider_cost_not_reported in capabilities.known_limitations
  end

  test "qualification cases cover every deterministic degradation branch" do
    cases = MockDegraded.qualification_cases()

    assert Enum.map(cases, & &1.branch) == @branches

    for case <- cases do
      assert case.category in [
               :capability_mismatch,
               :event_integrity,
               :runtime_failure,
               :capture_degraded,
               :capability_drift
             ]

      assert case.expected in [:fail_closed, :degraded_ok]
      assert is_binary(case.reason)
    end
  end

  test "malformed and out-of-order event branches fail closed through AgentRunner.run" do
    for branch <- [:malformed_events, :out_of_order_events, :duplicate_events] do
      assert {:error, finding} =
               AgentRunner.run(MockDegraded, %{}, %{}, %{}, scenario: branch)

      assert finding["severity"] == "blocking"
      assert finding["category"] == "adapter_conformance_failure"
      assert finding["branch"] == Atom.to_string(branch)
      assert finding["fail_closed"]
    end
  end

  test "partial tool-result capture is explicit degraded evidence" do
    assert {:ok, %RawRunResult{} = result} =
             AgentRunner.run(MockDegraded, %{}, %{}, %{},
               scenario: :partial_tool_result_capture,
               session_id: "mock-partial"
             )

    assert result.summary == "Mock degraded adapter captured partial tool results"
    assert result.tool_calls == [%{"name" => "shell", "capture" => "partial"}]
    assert result.metadata["adapter"] == "mock_degraded"
    assert result.metadata["session_id"] == "mock-partial"
    assert result.metadata["qualification_branch"] == "partial_tool_result_capture"
    assert result.metadata["degraded"] == true
  end

  test "missing cancellation fails closed with a stable branch key" do
    assert {:error, finding} = AgentRunner.cancel(MockDegraded, "mock-cancel")

    assert finding["category"] == "adapter_conformance_failure"
    assert finding["branch"] == "absent_cancellation"
    assert finding["fail_closed"]
  end
end
