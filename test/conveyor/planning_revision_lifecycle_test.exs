defmodule Conveyor.PlanningRevisionLifecycleTest do
  use ExUnit.Case, async: true

  alias Conveyor.Planning.RevisionLifecycle

  test "every imported source byte creates a source snapshot" do
    state = RevisionLifecycle.new("plan-1")

    state =
      state
      |> RevisionLifecycle.import_source!("Title: Build API\n", actor: "alice")
      |> RevisionLifecycle.import_source!("Title:  Build API\n", actor: "alice")

    assert Enum.map(state.source_snapshots, & &1.source_content_digest) |> Enum.uniq() |> length() ==
             2

    assert Enum.map(state.source_snapshots, & &1.snapshot_no) == [1, 2]
  end

  test "formatting-only edits create snapshots and draft checkpoints without publishing revisions" do
    state =
      "plan-1"
      |> RevisionLifecycle.new()
      |> RevisionLifecycle.import_source!("Title: Build API\n", actor: "alice")
      |> RevisionLifecycle.save_draft_checkpoint!("Title:  Build API\n", actor: "alice")

    assert [_snapshot] = state.source_snapshots
    assert [_checkpoint] = state.draft_checkpoints
    assert state.plan_revisions == []
  end

  test "published semantic revisions get immutable revision numbers" do
    state =
      "plan-1"
      |> RevisionLifecycle.new()
      |> RevisionLifecycle.import_source!("Title: Build API\n", actor: "alice")
      |> RevisionLifecycle.publish_revision!(%{"title" => "Build API"}, actor: "alice")

    assert [%{revision_no: 1, status: :published} = revision] = state.plan_revisions

    assert_raise ArgumentError, ~r/published PlanRevision is immutable/, fn ->
      RevisionLifecycle.update_revision!(state, revision.revision_id, %{"title" => "Changed"})
    end
  end
end
