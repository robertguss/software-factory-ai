defmodule Conveyor.E2ETracerTest do
  use Conveyor.DataCase, async: false

  alias Conveyor.Artifacts.Projector
  alias Conveyor.Demo
  alias Conveyor.Factory
  alias Conveyor.Factory.RunAttempt
  alias Conveyor.FactoryFixtures
  alias Conveyor.HumanIntegration
  alias Conveyor.Replay

  @base_commit String.duplicate("f", 40)

  setup do
    Process.put(:conveyor_seed_sample_git_fun, fn _repo_root, ["rev-parse", "HEAD"] ->
      {@base_commit <> "\n", 0}
    end)

    on_exit(fn -> Process.delete(:conveyor_seed_sample_git_fun) end)

    :ok
  end

  test "hermetic tracer reaches reported, replays, and regenerates artifacts" do
    blob_root = FactoryFixtures.temp_dir!("e2e-blobs")
    projection_root = FactoryFixtures.temp_dir!("e2e-projection")

    result =
      Demo.run!(
        blob_root: blob_root,
        projection_root: projection_root,
        base_commit: @base_commit
      )

    run_attempt = get_by_id!(RunAttempt, result.run_attempt.id)

    assert run_attempt.status == :reported
    assert result.run_slice.status == :succeeded
    assert File.exists?(Path.join(result.projection.projection_path, "manifest.json"))
    assert File.exists?(Path.join(result.projection.projection_path, "dossier.md"))

    HumanIntegration.record!(
      run_attempt_id: run_attempt.id,
      actor: "human@example.test",
      not_integrated: true,
      rationale: "E2E keeps merge manual."
    )

    timeline = Replay.timeline!()
    assert Enum.any?(timeline, &(&1["type"] == "run_attempt.transitioned"))
    assert Enum.any?(timeline, &(&1["type"] == "station.succeeded"))

    regenerated =
      Replay.project_run!(run_attempt.id,
        blob_root: blob_root,
        projection_root: projection_root,
        backend: Projector.LocalDisk
      )

    assert regenerated.bundle_root_sha256 == result.projection.bundle_root_sha256
  end

  @tag :live_agent
  test "live Pi tracer is gated behind explicit live_agent inclusion" do
    assert System.get_env("CONVEYOR_LIVE_PI") in [nil, "1"]
  end

  defp get_by_id!(resource, id) do
    resource
    |> Ash.read!(domain: Factory)
    |> Enum.find(&(&1.id == id)) ||
      raise ArgumentError, "#{inspect(resource)} #{id} was not found"
  end
end
