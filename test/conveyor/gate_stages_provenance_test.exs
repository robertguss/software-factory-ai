defmodule Conveyor.GateStagesProvenanceTest do
  use Conveyor.DataCase, async: false

  import Conveyor.FactoryFixtures

  alias Conveyor.Artifacts.BlobStore
  alias Conveyor.Factory
  alias Conveyor.Factory.Artifact
  alias Conveyor.Gate.Stages.ProvenanceAttestation

  setup do
    blob_root = temp_dir!("provenance-blobs")
    fixture = create_artifact_run!(blob_root: blob_root)
    %{blob_root: blob_root, run_attempt: fixture.run_attempt}
  end

  test "writes in-toto provenance artifact with subjects materials and invocation", %{
    blob_root: blob_root,
    run_attempt: run_attempt
  } do
    result = ProvenanceAttestation.run(valid_context(run_attempt, blob_root))

    assert result.status == :passed
    assert result.findings == []
    assert result.evidence_refs == ["provenance.intoto.json"]

    [artifact] =
      Artifact
      |> Ash.read!(domain: Factory)
      |> Enum.filter(&(&1.kind == "provenance" and &1.run_attempt_id == run_attempt.id))

    assert artifact.schema_version == "conveyor.provenance@1"
    assert artifact.projection_path == "provenance.intoto.json"

    statement =
      artifact.blob_ref
      |> BlobStore.read!(blob_root: blob_root)
      |> Jason.decode!()

    assert statement["_type"] == "https://in-toto.io/Statement/v1"
    assert statement["predicateType"] == "https://slsa.dev/provenance/v1"
    assert statement["schema_version"] == "conveyor.provenance@1"

    assert Enum.any?(statement["subject"], &(&1["name"] == "diff.patch"))
    assert Enum.any?(statement["subject"], &(&1["name"] == "evidence.json"))

    assert Enum.any?(
             statement["predicate"]["materials"],
             &(&1["uri"] == "container-image" and &1["digest"]["sha256"] == strip(digest("image")))
           )

    assert statement["predicate"]["invocation"]["parameters"]["policy_sha256"] == digest("policy")

    assert [
             %{
               "command" => "mix test",
               "exit_code" => 0,
               "output_sha256" => output_sha256
             }
           ] = statement["predicate"]["invocation"]["parameters"]["command_invocations"]

    assert output_sha256 == digest("test-output")
  end

  test "missing required provenance subject fails closed", %{
    blob_root: blob_root,
    run_attempt: run_attempt
  } do
    context =
      run_attempt
      |> valid_context(blob_root)
      |> Map.delete(:evidence_sha256)

    result = ProvenanceAttestation.run(context)

    assert result.status == :failed

    assert [%{"category" => "missing_provenance_subject", "subject" => "evidence.json"}] =
             result.findings

    refute Enum.any?(Ash.read!(Artifact, domain: Factory), &(&1.kind == "provenance"))
  end

  test "missing required material and invocation digests fail closed", %{
    blob_root: blob_root,
    run_attempt: run_attempt
  } do
    context =
      run_attempt
      |> valid_context(blob_root)
      |> Map.delete(:container_image_digest)
      |> Map.delete(:prompt_sha256)

    result = ProvenanceAttestation.run(context)

    assert result.status == :failed
    categories = Enum.map(result.findings, & &1["category"])
    assert "missing_material_digest" in categories
    assert "missing_invocation_digest" in categories
  end

  defp valid_context(run_attempt, blob_root) do
    %{
      run_attempt: run_attempt,
      run_attempt_id: run_attempt.id,
      blob_root: blob_root,
      base_commit: "abc123",
      patch_sha256: digest("patch"),
      evidence_sha256: digest("evidence"),
      run_spec_sha256: digest("run-spec"),
      policy_sha256: digest("policy"),
      prompt_sha256: digest("prompt"),
      container_image_digest: digest("image"),
      test_pack_sha256: digest("test-pack"),
      run_bundle_root_sha256: digest("bundle-root"),
      command_invocations: [
        %{
          argv: ["mix", "test"],
          exit_code: 0,
          output_sha256: digest("test-output")
        }
      ]
    }
  end

  defp strip("sha256:" <> digest), do: digest
  defp digest(label), do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, label), case: :lower)
end
