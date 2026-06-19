defmodule Conveyor.Eval.CassetteBridgeCountingRef do
  @moduledoc false
  # Delegates to ReferenceSolution but counts invocations, to prove the adapter is
  # NOT called on a cassette replay.
  @behaviour Conveyor.AgentRunner

  alias Conveyor.AgentRunner.ReferenceSolution

  @impl true
  def capabilities, do: ReferenceSolution.capabilities()

  @impl true
  def run(run_prompt, workspace, policy, opts) do
    Process.put(:cassette_ref_count, (Process.get(:cassette_ref_count) || 0) + 1)
    ReferenceSolution.run(run_prompt, workspace, policy, opts)
  end

  @impl true
  def cancel(session_id), do: ReferenceSolution.cancel(session_id)
end

defmodule Conveyor.Eval.CassetteBridgeTest do
  use Conveyor.DataCase, async: false

  alias Conveyor.AgentRunner.ReferenceSolution
  alias Conveyor.Eval.{BridgeFixtures, CassetteBridge, Schema}
  alias Conveyor.Eval.CassetteBridgeCountingRef, as: CountingRef

  @moduletag :eval
  @known_good "samples/tasks_service/.conveyor/canary/known_good.patch"
  @key "rung1_reference_solution"

  setup do
    {:ok, _} = Application.ensure_all_started(:jsv)
    Process.put(:cassette_ref_count, 0)
    :ok
  end

  # Record a fresh cassette (clearing any prior file first, so the first run records
  # rather than replays). The cassette is intentionally left on disk so the post-suite
  # `mix conveyor.eval.replay` step has a real corpus.
  defp record_fresh!(label) do
    File.rm(cassette_file())
    fixture = BridgeFixtures.sample_fixture!(label: label, patch_ref: @known_good)

    {:ok, result} =
      CassetteBridge.run(
        CountingRef,
        fixture.run_prompt,
        fixture.workspace,
        fixture.policy,
        opts(fixture)
      )

    {fixture, result}
  end

  defp opts(fixture) do
    [
      agent_session_id: fixture.agent_session.id,
      run_attempt_id: fixture.run_attempt.id,
      blob_root: fixture.blob_root,
      reference_patch: fixture.patch_ref,
      cassette_key: @key
    ]
  end

  defp cassette_file, do: Path.join("eval/cassettes", @key <> ".json")

  test "records a live run then replays it for $0 — adapter not invoked, RawRunResult byte-identical" do
    {fixture, live} = record_fresh!("cassette")
    assert Process.get(:cassette_ref_count) == 1

    {:ok, replayed} =
      CassetteBridge.run(
        CountingRef,
        fixture.run_prompt,
        fixture.workspace,
        fixture.policy,
        opts(fixture)
      )

    # The adapter was NOT called again — the replay came from the cassette.
    assert Process.get(:cassette_ref_count) == 1
    assert CassetteBridge.result_digest(replayed) == CassetteBridge.result_digest(live)
    assert replayed.metadata["adapter"] == "reference_solution"
  end

  test "the sealed cassette validates against conveyor.agent_cassette@1" do
    record_fresh!("cassette-schema")
    file = cassette_file() |> File.read!() |> Jason.decode!()
    assert file["cassette"]["seal_status"] == "sealed"
    assert Schema.validate(file["cassette"], "conveyor.agent_cassette@1") == :ok
  end

  test "a stale generation freshness misses (no false replay)" do
    record_fresh!("cassette-stale")
    stale = "sha256:0000000000000000000000000000000000000000000000000000000000000000"
    assert CassetteBridge.maybe_replay(@key, stale) == :miss
  end

  test "replay_corpus reports full fidelity over the recorded corpus" do
    record_fresh!("cassette-corpus")
    report = CassetteBridge.replay_corpus()
    assert report.total >= 1
    assert report.fidelity == 1.0
  end

  test "without :cassette_key it is a plain passthrough (back-compat)" do
    fixture =
      BridgeFixtures.sample_fixture!(label: "cassette-passthrough", patch_ref: @known_good)

    opts = [
      agent_session_id: fixture.agent_session.id,
      run_attempt_id: fixture.run_attempt.id,
      blob_root: fixture.blob_root,
      reference_patch: fixture.patch_ref
    ]

    {:ok, result} =
      CassetteBridge.run(
        ReferenceSolution,
        fixture.run_prompt,
        fixture.workspace,
        fixture.policy,
        opts
      )

    assert result.metadata["adapter"] == "reference_solution"
  end
end
