defmodule Conveyor.CassetteReplayAnchorSetTest do
  use ExUnit.Case, async: true

  alias Conveyor.Cassettes.ReplayAnchorSet

  @fixture_path "test/fixtures/phase-1.5/p15-b3/replay-anchor-set.json"

  test "builds a content-addressed anchor set from pre-change representative recordings" do
    anchor_set =
      ReplayAnchorSet.build!(
        recordings(),
        policy_digest: "sha256:policy",
        selected_before_change_ref: "git://base-before-change",
        expected_assertions: ["hybrid_replay_passes", "strict_replay_detects_divergence"]
      )

    assert anchor_set["schema_version"] == "conveyor.replay_anchor_set@1"
    assert anchor_set["selected_before_change_ref"] == "git://base-before-change"
    assert anchor_set["replay_anchor_set_digest"] =~ ~r/^sha256:[0-9a-f]{64}$/

    assert Enum.map(anchor_set["anchors"], & &1["category"]) == [
             "successful",
             "failed",
             "disputed",
             "safety_sensitive"
           ]

    assert Enum.any?(
             anchor_set["anchors"],
             &(&1["category"] == "failed" and &1["valuable_failure"])
           )
  end

  test "published fixture pins anchor categories and expected replay assertions" do
    fixture = @fixture_path |> File.read!() |> Jason.decode!()

    assert fixture["schema_version"] == "conveyor.replay_anchor_set@1"
    assert fixture["selected_before_change_ref"]
    assert fixture["replay_anchor_set_digest"] =~ ~r/^sha256:[0-9a-f]{64}$/

    assert Enum.map(fixture["anchors"], & &1["category"]) == [
             "successful",
             "failed",
             "disputed",
             "safety_sensitive"
           ]

    for anchor <- fixture["anchors"] do
      assert anchor["cassette_ref"] =~ ~r/^cassette:\/\//
      assert anchor["expected_replay_assertions"] != []
    end
  end

  defp recordings do
    [
      recording("successful", "cassette://successful-1"),
      recording("failed", "cassette://failed-1", valuable_failure: true),
      recording("disputed", "cassette://disputed-1"),
      recording("safety_sensitive", "cassette://safety-1")
    ]
  end

  defp recording(category, ref, opts \\ []) do
    %{
      category: category,
      cassette_ref: ref,
      expected_replay_assertions: ["hybrid_replay_passes"],
      valuable_failure: Keyword.get(opts, :valuable_failure, false)
    }
  end
end
