defmodule Conveyor.AgentRunner.FailureClassTest do
  @moduledoc "rt6k.6: transient (infra) vs work failure classification — allowlist-exact, fail-closed."
  use ExUnit.Case, async: true

  alias Conveyor.AgentRunner.FailureClass

  test "the watchdog timeout exit code is infra (timeout)" do
    assert {:infra, :timeout} = FailureClass.classify(%{exit_code: 124, output: ""})
  end

  test "provider rate-limit (429) is infra" do
    assert {:infra, :rate_limited} =
             FailureClass.classify(%{exit_code: 1, output: "Error: HTTP 429 Too Many Requests"})
  end

  test "provider overload / 5xx is infra" do
    assert {:infra, :provider_unavailable} =
             FailureClass.classify(%{
               exit_code: 1,
               output: "upstream returned 529 overloaded_error"
             })

    assert {:infra, :provider_unavailable} =
             FailureClass.classify(%{exit_code: 1, output: "503 Service Unavailable"})
  end

  test "connection refused/reset is infra" do
    assert {:infra, :connection_failed} =
             FailureClass.classify(%{exit_code: 1, output: "dial tcp: connection refused"})
  end

  test "container start failure is infra" do
    assert {:infra, :container_start_failed} =
             FailureClass.classify(%{exit_code: 125, output: "Error: container failed to start"})
  end

  test "a clean run (exit 0) is a work outcome, never infra" do
    assert :work = FailureClass.classify(%{exit_code: 0, output: "done"})
  end

  test "a nonzero exit WITH agent output is a work outcome (the agent ran and produced bad output)" do
    assert :work =
             FailureClass.classify(%{exit_code: 1, output: "diff --git a/x b/x\n+broken code"})
  end

  test "fail-closed: an ambiguous nonzero exit burns the attempt (classified :work)" do
    assert :work =
             FailureClass.classify(%{exit_code: 1, output: "assertion failed: expected 2 got 3"})
  end

  test "infra? is a convenience predicate over classify/1" do
    assert FailureClass.infra?(%{exit_code: 124, output: ""})
    refute FailureClass.infra?(%{exit_code: 0, output: "ok"})
  end
end
