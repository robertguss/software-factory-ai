defmodule Conveyor.PlanningRootAttestationsTest do
  use ExUnit.Case, async: true

  alias Conveyor.Planning.LayeredRoots
  alias Conveyor.Planning.RootAttestations

  test "emits a canonical unsigned in-toto statement over roots and supporting evidence" do
    roots = LayeredRoots.build(sample_input())

    result =
      RootAttestations.build(%{
        planning_run_id: "planning-run-1",
        layered_roots: roots,
        supporting_evidence_entries: sample_input().supporting_evidence_entries
      })

    assert result.status == :complete
    assert result.statement_digest =~ ~r/^sha256:[0-9a-f]{64}$/

    [statement] = result.statements
    assert statement["schema_version"] == "conveyor.attestation_statement@1"
    assert statement["_type"] == "https://in-toto.io/Statement/v1"
    assert statement["predicateType"] == "https://conveyor.dev/attestations/planning-roots/v1"
    assert statement["signature_status"] == "unsigned"

    assert Enum.map(statement["subject"], & &1["name"]) == [
             "conveyor:evidence/context_manifest/ctx-checkout",
             "conveyor:root/archive_bundle",
             "conveyor:root/epic_authority/checkout",
             "conveyor:root/review",
             "conveyor:root/shared_authority"
           ]

    assert %{"sha256" => shared_digest} =
             subject(statement, "conveyor:root/shared_authority")["digest"]

    assert shared_digest == roots.shared_authority_root["value"]
    assert statement["predicate"]["planning_run_id"] == "planning-run-1"

    assert statement["predicate"]["root_manifest_digests"]["shared_authority"] ==
             roots.shared_authority_root

    assert statement["predicate"]["canonicalization_profile"] == "rfc8785-jcs"

    assert_schema_valid!(statement, "conveyor.attestation_statement@1")
  end

  test "canonical statement digest is stable for equivalent evidence ordering" do
    roots = LayeredRoots.build(sample_input())

    first =
      RootAttestations.build(%{
        planning_run_id: "planning-run-1",
        layered_roots: roots,
        supporting_evidence_entries: [
          subject("verification_evidence", "verify-checkout", "evidence-v1"),
          subject("context_manifest", "ctx-checkout", "context-v1")
        ]
      })

    reordered =
      RootAttestations.build(%{
        planning_run_id: "planning-run-1",
        layered_roots: roots,
        supporting_evidence_entries: [
          subject("context_manifest", "ctx-checkout", "context-v1"),
          subject("verification_evidence", "verify-checkout", "evidence-v1")
        ]
      })

    assert first.statement_digest == reordered.statement_digest
    assert first.statements == reordered.statements
  end

  defp sample_input do
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
    }
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

  defp subject(statement, name) do
    Enum.find(statement["subject"], &(&1["name"] == name))
  end

  defp digest_ref(seed) do
    %{
      "schema_version" => "conveyor.digest_ref@1",
      "algorithm" => "sha256",
      "value" => :crypto.hash(:sha256, seed) |> Base.encode16(case: :lower)
    }
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
