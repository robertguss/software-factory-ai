defmodule Conveyor.RunEventStreamTest do
  @moduledoc """
  uevc.3: the ledger event stream projection. A run's events come from two link shapes — run-scoped
  (payload run_id) and attempt-scoped (run_attempt_id, bridged via run.started slice_ids). Both must
  appear, oldest-first, deterministically.
  """
  use Conveyor.DataCase, async: false

  alias Conveyor.Factory
  alias Conveyor.Factory.LedgerEvent
  alias Conveyor.FactoryFixtures
  alias Conveyor.RunEventStream

  defp event!(project_id, type, occurred_at, attrs) do
    Ash.create!(
      LedgerEvent,
      Map.merge(
        %{
          project_id: project_id,
          type: type,
          idempotency_key: "#{type}:#{occurred_at}",
          occurred_at: occurred_at,
          payload: %{}
        },
        attrs
      ),
      domain: Factory
    )
  end

  setup do
    %{project: project, slices: [slice], run_attempts: run_attempts} =
      FactoryFixtures.create_run_with_ledger!(terminal: :none, slices: [%{status: "passed"}])

    [attempt] = Map.fetch!(run_attempts, slice.id)
    run_id = "RUN-WATCH-#{binary_part(project.id, 0, 8)}"

    # run-scoped (payload run_id) — carries the slice_ids that bridge to attempt events
    event!(project.id, "run.started", ~U[2026-01-01 00:00:01.000000Z], %{
      payload: %{"run_id" => run_id, "slice_ids" => [slice.stable_key]}
    })

    # attempt-scoped (run_attempt_id, NO run_id) — only reachable via the bridge
    event!(project.id, "attempt.transitioned", ~U[2026-01-01 00:00:02.000000Z], %{
      slice_id: slice.id,
      run_attempt_id: attempt.id,
      payload: %{"to" => "gated"}
    })

    # run-scoped slice outcome
    event!(project.id, "run.slice_outcome", ~U[2026-01-01 00:00:03.000000Z], %{
      slice_id: slice.id,
      payload: %{"run_id" => run_id, "status" => "passed"}
    })

    # noise: a different run's event must NOT appear
    event!(project.id, "run.slice_outcome", ~U[2026-01-01 00:00:04.000000Z], %{
      payload: %{"run_id" => "OTHER-RUN", "status" => "parked"}
    })

    %{run_id: run_id}
  end

  test "gathers run-scoped + attempt-scoped events, oldest-first, excluding other runs", %{
    run_id: run_id
  } do
    stream = RunEventStream.for_run(run_id)

    assert Enum.map(stream, & &1.type) == [
             "run.started",
             "attempt.transitioned",
             "run.slice_outcome"
           ]

    # the attempt event (no run_id in payload) was reached through the slice→attempt bridge
    assert Enum.any?(stream, &(&1.type == "attempt.transitioned" and &1.run_attempt_id != nil))
    # the other run's event is absent
    refute Enum.any?(stream, &(&1.payload["run_id"] == "OTHER-RUN"))
  end

  test "an unknown run id yields an empty stream, no crash" do
    assert RunEventStream.for_run("nope") == []
  end
end
