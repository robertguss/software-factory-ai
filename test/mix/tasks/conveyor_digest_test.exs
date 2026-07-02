defmodule Mix.Tasks.ConveyorDigestTest do
  @moduledoc "a3hf.1.1.3: the headless mix conveyor.digest task over the run ledger."
  use Conveyor.DataCase, async: false

  import ExUnit.CaptureIO

  alias Conveyor.Factory
  alias Conveyor.Factory.Project
  alias Conveyor.Ledger

  setup do
    project =
      Ash.create!(
        Project,
        %{
          name: "Digest",
          local_path: "/tmp/digest-#{System.unique_integer([:positive])}",
          default_branch: "main"
        },
        domain: Factory
      )

    run_started(project.id, "RUN-A", ["S1", "S2"])
    slice_outcome(project.id, "RUN-A", "S1", 1, "passed")
    slice_outcome(project.id, "RUN-A", "S2", 2, "parked")

    test_pid = self()
    Process.put(:conveyor_digest_exit_fun, fn code -> send(test_pid, {:exit, code}) end)
    on_exit(fn -> Process.delete(:conveyor_digest_exit_fun) end)
    :ok
  end

  test "--format json folds the recorded run into the digest with correct dispositions" do
    json = run_digest(["--format", "json"]) |> Jason.decode!()

    assert json["totals"]["runs"] == 1
    [run] = json["runs"]
    assert run["run_id"] == "RUN-A"
    assert run["dispositions"]["merged"] == 1
    assert run["dispositions"]["parked"] == 1
    assert run["needs_judgment"] == 1
    assert_received {:exit, 0}
  end

  test "--format md renders the recorded run as Markdown" do
    md = run_digest(["--format", "md"])
    assert md =~ "# Morning Digest"
    assert md =~ "| RUN-A |"
  end

  defp run_digest(args) do
    capture_io(fn ->
      Mix.Task.reenable("conveyor.digest")
      Mix.Task.run("conveyor.digest", args)
    end)
    |> String.trim()
  end

  defp run_started(project_id, run_id, slice_ids) do
    Ledger.write!(%{
      project_id: project_id,
      idempotency_key: "#{run_id}:started",
      type: "run.started",
      payload: %{"run_id" => run_id, "slice_ids" => slice_ids},
      occurred_at: DateTime.utc_now()
    })
  end

  defp slice_outcome(project_id, run_id, slice_id, sequence, status) do
    Ledger.write!(%{
      project_id: project_id,
      idempotency_key: "#{run_id}:#{slice_id}:#{sequence}",
      type: "run.slice_outcome",
      payload: %{
        "run_id" => run_id,
        "slice_id" => slice_id,
        "sequence" => sequence,
        "status" => status,
        "blocked_by" => [],
        "findings" => []
      },
      occurred_at: DateTime.utc_now()
    })
  end
end
