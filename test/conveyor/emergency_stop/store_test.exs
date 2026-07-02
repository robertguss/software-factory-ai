defmodule Conveyor.EmergencyStop.StoreTest do
  @moduledoc """
  a3hf.2.1.4: durable, ledger-backed emergency-stop activation. A trip is recorded as a
  `conveyor.emergency_stop_state@1` ledger event; `engaged?/2` reads the latest engaged/cleared
  transition. The full trip-on-breach + halt e2e is the Tests-sibling a3hf.2.1.5.
  """
  use Conveyor.DataCase, async: false

  alias Conveyor.EmergencyStop.Store
  alias Conveyor.Factory
  alias Conveyor.Factory.LedgerEvent
  alias Conveyor.Factory.Project

  defp project! do
    Ash.create!(
      Project,
      %{
        name: "EStop #{System.unique_integer([:positive])}",
        local_path: "/tmp/estop-#{System.unique_integer([:positive])}",
        default_branch: "main"
      },
      domain: Factory
    )
  end

  test "trip! engages and records a durable emergency_stop_state@1 event" do
    project = project!()

    state =
      Store.trip!(:project, project.id,
        project_id: project.id,
        actor: "budget-guard",
        reason: "budget_envelope_breach",
        trace_id: "trace-estop"
      )

    assert state.status == :engaged
    assert Store.engaged?(:project, project.id)

    [event] =
      LedgerEvent
      |> Ash.read!(domain: Factory)
      |> Enum.filter(&(&1.type == "emergency_stop.engaged"))

    assert event.payload["schema_version"] == "conveyor.emergency_stop_state@1"
    assert event.payload["status"] == "engaged"
    assert event.payload["reason"] == "budget_envelope_breach"
    assert event.payload["project_id"] == project.id
  end

  test "engaged?/2 is false before any trip" do
    refute Store.engaged?(:project, project!().id)
  end

  test "trip! is idempotent for the same scope + reason" do
    project = project!()
    opts = [project_id: project.id, actor: "op", reason: "budget_envelope_breach", trace_id: "t"]

    Store.trip!(:project, project.id, opts)
    Store.trip!(:project, project.id, opts)

    engaged =
      LedgerEvent
      |> Ash.read!(domain: Factory)
      |> Enum.count(&(&1.type == "emergency_stop.engaged"))

    assert engaged == 1
  end

  test "clear! records a cleared transition and engaged?/2 flips back to false" do
    project = project!()

    state =
      Store.trip!(:project, project.id,
        project_id: project.id,
        actor: "op",
        reason: "budget_envelope_breach",
        trace_id: "t"
      )

    assert Store.engaged?(:project, project.id)

    Store.clear!(state,
      project_id: project.id,
      actor: "operator",
      human_decision_id: "hd-1"
    )

    refute Store.engaged?(:project, project.id)
  end

  test "a stop on one project does not engage another" do
    a = project!()
    b = project!()

    Store.trip!(:project, a.id,
      project_id: a.id,
      actor: "op",
      reason: "budget_envelope_breach",
      trace_id: "t"
    )

    assert Store.engaged?(:project, a.id)
    refute Store.engaged?(:project, b.id)
  end
end
