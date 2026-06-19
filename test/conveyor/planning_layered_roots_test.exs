defmodule Conveyor.PlanningLayeredRootsTest do
  use ExUnit.Case, async: true

  alias Conveyor.Planning.LayeredRoots

  test "review-only changes leave authority roots stable and update review and archive roots" do
    base = LayeredRoots.build(sample_input())

    updated_review =
      LayeredRoots.build(
        sample_input(%{
          review_projection_entries: [
            subject("approval_projection", "projection-checkout", "review-copy-v2")
          ]
        })
      )

    assert base.status == :complete
    assert base.shared_authority_root == updated_review.shared_authority_root
    assert base.epic_authority_roots == updated_review.epic_authority_roots
    assert base.review_root != updated_review.review_root
    assert base.archive_bundle_root != updated_review.archive_bundle_root

    assert base.shared_authority_manifest["root_kind"] == "shared_authority"
    assert base.review_manifest["root_kind"] == "review"
    assert base.archive_bundle_manifest["root_kind"] == "archive_bundle"

    assert sorted_subjects(base.shared_authority_manifest) == [
             "constraint_set",
             "plan_revision",
             "policy_bundle"
           ]

    refute root_contains_subject_class?(base.review_manifest, "approval_record")
    refute root_contains_subject_class?(base.shared_authority_manifest, "approval_record")
    assert base.excluded_approval_record_ref["kind"] == "approval_record"

    assert_schema_valid!(base.shared_authority_manifest, "conveyor.root_manifest@1")
    assert_schema_valid!(base.epic_authority_manifests["checkout"], "conveyor.root_manifest@1")
    assert_schema_valid!(base.review_manifest, "conveyor.root_manifest@1")
    assert_schema_valid!(base.archive_bundle_manifest, "conveyor.root_manifest@1")
  end

  test "semantic shared authority changes alter the shared root without changing epic authority" do
    base = LayeredRoots.build(sample_input())

    updated_policy =
      LayeredRoots.build(
        sample_input(%{
          shared_authority_entries: [
            subject("plan_revision", "plan-rev-1", "plan-v1"),
            subject("constraint_set", "constraints-1", "constraints-v1"),
            subject("policy_bundle", "policy-main", "policy-v2")
          ]
        })
      )

    assert base.shared_authority_root != updated_policy.shared_authority_root
    assert base.epic_authority_roots == updated_policy.epic_authority_roots
    assert base.review_root == updated_policy.review_root
    assert base.archive_bundle_root != updated_policy.archive_bundle_root
  end

  defp sample_input(overrides \\ %{}) do
    Map.merge(
      %{
        shared_authority_entries: [
          subject("policy_bundle", "policy-main", "policy-v1"),
          subject("plan_revision", "plan-rev-1", "plan-v1"),
          subject("constraint_set", "constraints-1", "constraints-v1")
        ],
        epic_authority_entries: %{
          "checkout" => [
            subject("slice_contract", "slice-checkout", "contract-v1"),
            subject("verification_obligation", "verify-checkout", "obligation-v1")
          ]
        },
        review_projection_entries: [
          subject("approval_projection", "projection-checkout", "review-copy-v1")
        ],
        supporting_evidence_entries: [
          subject("context_manifest", "ctx-checkout", "context-v1")
        ],
        approval_record_ref: subject("approval_record", "approval-checkout", "approval-v1")
      },
      overrides
    )
  end

  defp subject(kind, id, digest_seed) do
    %{
      "subject_class" => kind,
      "ref" => %{
        "schema_version" => "conveyor.subject_ref@1",
        "kind" => kind,
        "id_or_key" => id,
        "digest" => digest_ref(digest_seed)
      }
    }
  end

  defp digest_ref(seed) do
    %{
      "schema_version" => "conveyor.digest_ref@1",
      "algorithm" => "sha256",
      "value" => :crypto.hash(:sha256, seed) |> Base.encode16(case: :lower)
    }
  end

  defp sorted_subjects(manifest) do
    Enum.map(manifest["sorted_entries"], & &1["subject_class"])
  end

  defp root_contains_subject_class?(manifest, subject_class) do
    Enum.any?(manifest["sorted_entries"], &(&1["subject_class"] == subject_class))
  end

  defp assert_schema_valid!(resource, schema_name) do
    schema =
      "docs/schemas/#{schema_name}.json"
      |> File.read!()
      |> Jason.decode!()
      |> JSV.build!()

    assert {:ok, _validated} = JSV.validate(resource, schema)
  end
end
