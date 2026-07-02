defmodule Conveyor.AgentRunner.AdapterBaseRetryTest do
  @moduledoc "rt6k.6: infra failures are retried at the adapter seam, never burning an attempt."
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Conveyor.AgentRunner.AdapterBase

  # A scripted exec: pops the next {stdout, exit_code} per call; repeats the last when exhausted.
  # Tracks how many times it was invoked so we can assert retry behavior.
  defp scripted(outcomes) do
    {:ok, pid} = Agent.start_link(fn -> %{queue: outcomes, calls: 0} end)
    exec = fn _prompt, _ws, _opts -> Agent.get_and_update(pid, &pop/1) end
    {exec, pid}
  end

  defp pop(%{queue: queue, calls: calls}) do
    {value, rest} = next_outcome(queue)
    {value, %{queue: rest, calls: calls + 1}}
  end

  defp next_outcome([only]), do: {only, [only]}
  defp next_outcome([head | tail]), do: {head, tail}

  defp calls(pid), do: Agent.get(pid, & &1.calls)

  defp opts, do: [sleep_fn: fn _ -> :ok end, adapter: "codex"]

  test "a transient 5xx twice then success completes without burning an attempt" do
    {exec, pid} =
      scripted([{"529 overloaded_error", 1}, {"529 overloaded_error", 1}, {"diff --git a/x", 0}])

    assert {"diff --git a/x", 0, nil} =
             AdapterBase.run_with_timeout(exec, "p", "/ws", opts(), 5_000)

    assert calls(pid) == 3
  end

  test "persistent infra failure returns a typed infra_error after the retry cap is exhausted" do
    {exec, pid} = scripted([{"503 Service Unavailable", 1}])

    assert {"503 Service Unavailable", 1, infra} =
             AdapterBase.run_with_timeout(exec, "p", "/ws", opts(), 5_000)

    # rt6k.7: the exhausted infra outcome carries its class + retry count for the loop to park on.
    assert is_binary(infra["class"])
    assert infra["retries"] == 2

    # initial call + 2 retries (default cap)
    assert calls(pid) == 3
  end

  test "a work outcome (bad diff) is never retried and carries no infra metadata" do
    {exec, pid} = scripted([{"assertion failed: expected 2 got 3", 1}])

    assert {"assertion failed: expected 2 got 3", 1, nil} =
             AdapterBase.run_with_timeout(exec, "p", "/ws", opts(), 5_000)

    assert calls(pid) == 1
  end

  test "a clean success is not retried" do
    {exec, pid} = scripted([{"ok", 0}])
    assert {"ok", 0, nil} = AdapterBase.run_with_timeout(exec, "p", "/ws", opts(), 5_000)
    assert calls(pid) == 1
  end

  test "each infra retry logs the class, adapter, and retry index" do
    {exec, _pid} = scripted([{"429 rate limit", 1}, {"ok", 0}])

    log =
      capture_log(fn ->
        AdapterBase.run_with_timeout(exec, "p", "/ws", opts(), 5_000)
      end)

    assert log =~ "agent infra retry"
    assert log =~ "class=rate_limited"
    assert log =~ "adapter=codex"
    assert log =~ "retry=1/2"
  end
end
