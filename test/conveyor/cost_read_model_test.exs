defmodule Conveyor.Cost.ReadModelTest do
  @moduledoc "a3hf.2.1.1: cost read-model — per-dimension totals + remaining budget."
  use ExUnit.Case, async: true

  alias Conveyor.Cost.ReadModel

  defp usage(run, slice, adapter, attempt, tokens, cost, latency) do
    %{
      "schema_version" => "conveyor.agent_usage@1",
      "run_id" => run,
      "slice_id" => slice,
      "adapter" => adapter,
      "attempt_no" => attempt,
      "tokens" => tokens,
      "cost_usd_estimated" => cost,
      "latency_ms" => latency
    }
  end

  defp fixture do
    [
      usage("R1", "S1", "codex", 1, 100, 0.10, 1_000),
      usage("R1", "S1", "codex", 2, 200, 0.20, 2_000),
      usage("R1", "S2", "claude_code", 1, 300, 0.30, 3_000),
      usage("R2", "S3", "codex", 1, 400, 0.40, 4_000)
    ]
  end

  test "overall totals sum tokens, cost, and latency across all records" do
    %{totals: t} = ReadModel.aggregate(fixture())
    assert t.tokens == 1_000
    assert_in_delta t.cost_usd, 1.00, 1.0e-9
    assert t.latency_ms == 10_000
    assert t.count == 4
  end

  test "per-dimension totals are keyed by run, slice, agent, and attempt" do
    agg = ReadModel.aggregate(fixture())

    assert agg.by_run["R1"].tokens == 600
    assert agg.by_run["R2"].tokens == 400

    assert agg.by_slice["S1"].tokens == 300
    assert agg.by_slice["S1"].count == 2

    assert agg.by_agent["codex"].tokens == 700
    assert agg.by_agent["claude_code"].tokens == 300

    assert agg.by_attempt[1].tokens == 800
    assert agg.by_attempt[2].tokens == 200
  end

  test "remaining budget subtracts totals from the budget envelope limits" do
    envelope = %{
      "schema_version" => "conveyor.budget_envelope@1",
      "token_limit" => 5_000,
      "cost_limit" => 2.50
    }

    %{remaining: r} = ReadModel.aggregate(fixture(), envelope)
    assert r.tokens == 4_000
    assert_in_delta r.cost_usd, 1.50, 1.0e-9
    refute r.over_budget?
  end

  test "remaining budget flags an overrun when totals exceed the envelope" do
    envelope = %{"token_limit" => 500, "cost_limit" => 0.50}
    %{remaining: r} = ReadModel.aggregate(fixture(), envelope)
    assert r.tokens == -500
    assert r.over_budget?
  end

  test "remaining is nil when no budget envelope is supplied" do
    assert ReadModel.aggregate(fixture()).remaining == nil
  end

  test "aggregate over no records yields zeroed totals" do
    %{totals: t} = ReadModel.aggregate([])
    assert t == %{tokens: 0, cost_usd: 0.0, latency_ms: 0, count: 0}
  end
end
