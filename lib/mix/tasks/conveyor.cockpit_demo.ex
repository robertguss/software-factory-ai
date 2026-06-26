defmodule Mix.Tasks.Conveyor.CockpitDemo do
  @moduledoc """
  Seed a representative cockpit demo (`/runs`) for manual verification.

      mix conveyor.cockpit_demo

  Builds one plan (two epics) whose nodes cover every computed state — done,
  ready_idle, blocked, parked, skipped, running, stalled, failed — plus an older
  run for the switcher. Run it against a clean dev DB (`mix ecto.reset` first).

  For live updates, drive `Conveyor.CockpitDemo` from an `iex -S mix phx.server`
  session (see that module's docs); dev has no automatic outbox drain.
  """

  use Mix.Task

  alias Conveyor.CockpitDemo

  @shortdoc "Seed the cockpit demo run for manual /runs verification"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    summary = CockpitDemo.seed!()

    Mix.shell().info("""
    Seeded cockpit demo:
      plan_id:  #{summary.plan_id}
      slices:   #{summary.slices}
      live run: #{summary.live_run}
      old run:  #{summary.old_run}

    Open http://localhost:4000/runs (start the server with `iex -S mix phx.server`
    to also use the live Conveyor.CockpitDemo helpers).
    """)
  end
end
