defmodule Conveyor.Budget.ReservationGateTest do
  @moduledoc """
  a3hf.2.1.3: reserve-before-spend enforcement. A call that would exceed the run's budget envelope
  is refused before spending; a within-budget call reserves. Pure decision function — the full
  driver/e2e is the Tests-sibling a3hf.2.1.5.
  """
  use ExUnit.Case, async: true

  alias Conveyor.Budget.ReservationGate

  defp budget(overrides \\ %{}) do
    Map.merge(
      %{
        status: :active,
        max_tokens: nil,
        consumed_tokens: nil,
        max_cost_cents: nil,
        consumed_cost_cents: nil
      },
      overrides
    )
  end

  test "an uncapped, active budget reserves any call" do
    assert {:ok, reservation} = ReservationGate.reserve(budget(), %{tokens: 10_000, cost: 500})
    assert reservation.status == :reserved
  end

  test "a within-budget call reserves" do
    b =
      budget(%{
        max_tokens: 1000,
        consumed_tokens: 100,
        max_cost_cents: 500,
        consumed_cost_cents: 50
      })

    assert {:ok, %{status: :reserved}} = ReservationGate.reserve(b, %{tokens: 400, cost: 100})
  end

  test "a call whose token request exceeds the remaining envelope is refused" do
    b = budget(%{max_tokens: 1000, consumed_tokens: 900})
    assert {:deny, :token_limit} = ReservationGate.reserve(b, %{tokens: 500})
  end

  test "a call whose cost request exceeds the remaining envelope is refused" do
    b = budget(%{max_cost_cents: 500, consumed_cost_cents: 450})
    assert {:deny, :cost_limit} = ReservationGate.reserve(b, %{cost: 100})
  end

  test "a fully-consumed (zero-remaining) token budget refuses the next call even with no estimate" do
    b = budget(%{max_tokens: 1000, consumed_tokens: 1000})
    assert {:deny, :token_limit} = ReservationGate.reserve(b, %{})
  end

  test "an already-exhausted budget refuses regardless of request" do
    assert {:deny, :budget_exhausted} =
             ReservationGate.reserve(budget(%{status: :exhausted}), %{})
  end

  test "commit marks a reservation committed with actuals" do
    {:ok, reservation} = ReservationGate.reserve(budget(), %{tokens: 100})
    assert {:ok, committed} = ReservationGate.commit(reservation, %{tokens: 90})
    assert committed.status == :committed
    assert committed.committed_actuals == %{tokens: 90}
  end
end
