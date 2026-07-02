defmodule Conveyor.Cost.EstimatorTest do
  @moduledoc "a3hf.2.2.2: cost estimator from historical agent_usage — range, not point."
  use ExUnit.Case, async: true

  alias Conveyor.Cost.Estimator

  defp hist(archetype, tokens, cost) do
    %{"archetype" => archetype, "tokens" => tokens, "cost_usd_estimated" => cost}
  end

  test "estimates a plan from per-archetype history as a low/expected/high range" do
    history = [
      hist("implement", 100, 0.10),
      hist("implement", 300, 0.30),
      hist("review", 50, 0.05)
    ]

    assert {:ok, est} = Estimator.estimate(["implement", "review"], history)

    # implement: min 100 / mean 200 / max 300 ; review: 50/50/50
    assert est.tokens.low == 150
    assert est.tokens.expected == 250
    assert est.tokens.high == 350
    assert_in_delta est.cost_usd.expected, 0.25, 1.0e-9
    assert est.coverage.covered == 2
    assert est.coverage.uncovered == 0
  end

  test "expected sits within the low/high band" do
    history = [hist("implement", 100, 0.1), hist("implement", 500, 0.5)]
    {:ok, est} = Estimator.estimate(["implement"], history)
    assert est.tokens.low <= est.tokens.expected
    assert est.tokens.expected <= est.tokens.high
  end

  test "empty history yields an explicit no-basis, not a fake number" do
    assert {:no_basis, reason} = Estimator.estimate(["implement"], [])
    assert reason =~ "no historical"
  end

  test "a plan whose archetypes have no history is no-basis" do
    history = [hist("explore", 10, 0.01)]
    assert {:no_basis, _} = Estimator.estimate(["implement", "review"], history)
  end

  test "partial coverage estimates the covered slices and reports the uncovered count" do
    history = [hist("implement", 200, 0.2)]
    {:ok, est} = Estimator.estimate(["implement", "novel_archetype"], history)

    assert est.tokens.expected == 200
    assert est.coverage.covered == 1
    assert est.coverage.uncovered == 1
  end
end
