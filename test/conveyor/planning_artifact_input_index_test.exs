defmodule Conveyor.PlanningArtifactInputIndexTest do
  use ExUnit.Case, async: true

  alias Conveyor.Planning.ArtifactInputIndex

  test "indexes artifact inputs by role and previews invalidation for changed subjects" do
    index =
      ArtifactInputIndex.build(%{
        emitted_artifacts: [
          %{
            artifact_id: "work_graph:1",
            inputs: [
              input("plan_revision", "plan-1", "semantic"),
              input("approval_root", "approval-1", "authority"),
              input("gate_result", "gate-1", "verified_by_gate"),
              input("repo_inventory", "repo-1", "advisory"),
              input("rendered_review", "review-1", "presentation")
            ]
          }
        ],
        created_at: "2026-06-19T00:00:00Z"
      })

    assert Enum.map(index.artifact_inputs, & &1["role"]) == [
             "semantic",
             "authority",
             "verified_by_gate",
             "advisory",
             "presentation"
           ]

    assert Enum.map(index.artifact_inputs, & &1["invalidation_policy"]) == [
             "invalidate_on_change",
             "invalidate_on_change",
             "invalidate_on_change",
             "warn_on_change",
             "ignore_after_capture"
           ]

    assert ArtifactInputIndex.preview_changed(index, [
             %{subject_kind: "repo_inventory", subject_id: "repo-1"},
             %{subject_kind: "approval_root", subject_id: "approval-1"}
           ]) == [
             %{
               consumer_artifact_id: "work_graph:1",
               input_subject_kind: "approval_root",
               input_subject_id: "approval-1",
               role: "authority",
               invalidation_policy: "invalidate_on_change"
             },
             %{
               consumer_artifact_id: "work_graph:1",
               input_subject_kind: "repo_inventory",
               input_subject_id: "repo-1",
               role: "advisory",
               invalidation_policy: "warn_on_change"
             }
           ]
  end

  test "unknown semantic-vs-advisory inputs use stronger invalidation" do
    index =
      ArtifactInputIndex.build(%{
        emitted_artifacts: [
          %{
            artifact_id: "work_graph:1",
            inputs: [
              input("ambiguous_source", "source-1", "unknown")
            ]
          }
        ],
        created_at: "2026-06-19T00:00:00Z"
      })

    assert [
             %{
               "role" => "semantic",
               "invalidation_policy" => "invalidate_on_change",
               "input_subject_kind" => "ambiguous_source"
             }
           ] = index.artifact_inputs
  end

  defp input(kind, id, role) do
    %{
      subject_kind: kind,
      subject_id: id,
      digest: digest("#{kind}:#{id}"),
      role: role
    }
  end

  defp digest(label), do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, label), case: :lower)
end
