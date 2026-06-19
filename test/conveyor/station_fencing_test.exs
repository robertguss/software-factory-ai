defmodule Conveyor.StationFencingTest do
  use ExUnit.Case, async: true

  alias Conveyor.Factory.StationRun
  alias Conveyor.Station

  test "StationRun exposes lease epoch, owner instance, acquisition, and trace fields" do
    attribute_names =
      StationRun
      |> Ash.Resource.Info.attributes()
      |> Enum.map(& &1.name)

    assert :lease_epoch in attribute_names
    assert :lease_owner_instance_id in attribute_names
    assert :lease_acquired_at in attribute_names
    assert :lease_expires_at in attribute_names
    assert :heartbeat_at in attribute_names
    assert :trace_id in attribute_names
  end

  test "fencing tokens are stable and stale epochs are rejected before writes" do
    current = %StationRun{id: "station-run-1", lease_epoch: 2}
    stale = %StationRun{id: "station-run-1", lease_epoch: 1}

    assert Station.fencing_token(current) == "station-run-1:2"
    assert :ok = Station.ensure_current_lease!(current, current)

    assert_raise ArgumentError,
                 ~r/stale lease_epoch 1 for StationRun station-run-1; current epoch is 2/,
                 fn ->
                   Station.ensure_current_lease!(stale, current)
                 end
  end

  test "claim controls validate admission, generation, stop, grant, budget, and prerequisites" do
    controls = %{
      admission_permit: %{status: :active, control_generation: 7},
      control_generation: 7,
      emergency_stop: :clear,
      grant_status: :active,
      budget_status: :reserved,
      prerequisites: :satisfied
    }

    assert :ok = Station.validate_claim_controls!(controls)

    assert_raise ArgumentError, ~r/control generation mismatch/, fn ->
      Station.validate_claim_controls!(%{controls | control_generation: 8})
    end

    assert_raise ArgumentError, ~r/emergency stop is engaged/, fn ->
      Station.validate_claim_controls!(%{controls | emergency_stop: :engaged})
    end

    assert_raise ArgumentError, ~r/grant is not active/, fn ->
      Station.validate_claim_controls!(%{controls | grant_status: :revoked})
    end

    assert_raise ArgumentError, ~r/budget is not reserved/, fn ->
      Station.validate_claim_controls!(%{controls | budget_status: :expired})
    end

    assert_raise ArgumentError, ~r/prerequisites are not satisfied/, fn ->
      Station.validate_claim_controls!(%{controls | prerequisites: :missing})
    end
  end
end
