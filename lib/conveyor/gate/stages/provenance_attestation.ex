defmodule Conveyor.Gate.Stages.ProvenanceAttestation do
  @moduledoc """
  Gate stage 12: generates and validates a local in-toto/SLSA-shaped provenance
  artifact.
  """

  @behaviour Conveyor.Gate.Stage

  alias Conveyor.Artifacts.BlobStore
  alias Conveyor.Factory
  alias Conveyor.Factory.Artifact
  alias Conveyor.Gate.StageResult

  @schema_version "conveyor.provenance@1"
  @statement_type "https://in-toto.io/Statement/v1"
  @predicate_type "https://slsa.dev/provenance/v1"
  @default_builder_id "conveyor/phase1-local"
  @default_build_type "conveyor.slice.gate@1"
  @default_subjects ["diff.patch", "evidence.json"]
  @required_materials [
    {"source", :base_commit, "gitCommit"},
    {"container-image", :container_image_digest, "sha256"},
    {"test-pack", :test_pack_sha256, "sha256"}
  ]
  @required_invocation_digests [:run_spec_sha256, :policy_sha256, :prompt_sha256]

  @impl true
  def run(context, _opts \\ []) do
    statement = statement(context)
    findings = findings(context, statement)
    persisted = maybe_persist(statement, findings, context)

    %StageResult{
      key: "provenance_attestation",
      status: status(findings),
      required?: true,
      findings: findings,
      evidence_refs: evidence_refs(persisted),
      input_digests: input_digests(context, statement),
      output_digest: "sha256:" <> BlobStore.sha256(canonical_json(statement))
    }
  end

  defp statement(context) do
    %{
      "schema_version" => @schema_version,
      "_type" => @statement_type,
      "subject" => subjects(context),
      "predicateType" => @predicate_type,
      "predicate" => %{
        "builder" => %{"id" => value(context, :builder_id) || @default_builder_id},
        "buildType" => value(context, :build_type) || @default_build_type,
        "materials" => materials(context),
        "invocation" => %{
          "parameters" => invocation_parameters(context)
        },
        "metadata" => %{
          "local_unsigned" => true,
          "run_bundle_root_sha256" => run_bundle_root_sha256(context)
        }
      }
    }
  end

  defp subjects(context) do
    context
    |> value(:provenance_subjects)
    |> List.wrap()
    |> Kernel.++(artifact_subjects(value(context, :artifacts) || []))
    |> Kernel.++(default_subjects(context))
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&normalize_subject/1)
    |> dedupe_by("name")
  end

  defp artifact_subjects(artifacts) do
    Enum.map(artifacts, fn artifact ->
      %{
        "name" => value(artifact, :projection_path),
        "digest" => %{"sha256" => normalize_sha(value(artifact, :sha256))}
      }
    end)
  end

  defp default_subjects(context) do
    [
      subject(
        "diff.patch",
        value(context, :patch_sha256) || value(value(context, :patch_set), :patch_sha256)
      ),
      subject(
        "evidence.json",
        value(context, :evidence_sha256) || value(value(context, :evidence), :sha256)
      )
    ]
  end

  defp subject(_name, nil), do: nil

  defp subject(name, sha256),
    do: %{"name" => name, "digest" => %{"sha256" => normalize_sha(sha256)}}

  defp normalize_subject(subject) do
    name = value(subject, :name) || value(subject, :path)
    digest = value(subject, :digest)
    sha256 = normalize_sha(value(digest, :sha256) || value(subject, :sha256))

    %{"name" => name, "digest" => %{"sha256" => sha256}}
  end

  defp materials(context) do
    explicit =
      context
      |> value(:provenance_materials)
      |> List.wrap()
      |> Enum.map(&normalize_material/1)

    defaults =
      Enum.map(@required_materials, fn {uri, context_key, digest_key} ->
        material(uri, digest_key, material_digest(context, context_key))
      end)

    (explicit ++ defaults)
    |> Enum.reject(&is_nil/1)
    |> dedupe_by("uri")
  end

  defp normalize_material(material) do
    uri = value(material, :uri)
    digest = value(material, :digest) || %{}

    cond do
      is_nil(uri) ->
        nil

      git_commit = value(digest, :gitCommit) ->
        material(uri, "gitCommit", git_commit)

      sha256 = value(digest, :sha256) || value(material, :sha256) ->
        material(uri, "sha256", normalize_sha(sha256))

      true ->
        %{"uri" => uri, "digest" => %{}}
    end
  end

  defp material(_uri, _digest_key, nil), do: nil

  defp material(uri, "sha256", digest),
    do: %{"uri" => uri, "digest" => %{"sha256" => normalize_sha(digest)}}

  defp material(uri, digest_key, digest), do: %{"uri" => uri, "digest" => %{digest_key => digest}}

  defp material_digest(context, :base_commit) do
    value(context, :base_commit) ||
      value(value(context, :run_spec), :base_commit) ||
      value(value(context, :run_attempt), :base_commit)
  end

  defp material_digest(context, key),
    do: value(context, key) || value(value(context, :run_spec), key)

  defp invocation_parameters(context) do
    digest_parameters =
      Map.new(@required_invocation_digests, fn key ->
        {Atom.to_string(key), value(context, key) || value(value(context, :run_spec), key)}
      end)

    digest_parameters
    |> Map.put(
      "patch_sha256",
      value(context, :patch_sha256) || value(value(context, :patch_set), :patch_sha256)
    )
    |> Map.put("command_invocations", command_invocations(context))
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp command_invocations(context) do
    context
    |> value(:command_invocations)
    |> List.wrap()
    |> Enum.map(fn invocation ->
      %{
        "command" => value(invocation, :command) || command_line(value(invocation, :argv)),
        "argv" => value(invocation, :argv),
        "exit_code" => value(invocation, :exit_code),
        "output_sha256" => value(invocation, :output_sha256)
      }
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()
    end)
  end

  defp findings(context, statement) do
    []
    |> Kernel.++(subject_findings(context, statement))
    |> Kernel.++(material_findings(statement))
    |> Kernel.++(invocation_digest_findings(statement))
  end

  defp subject_findings(context, statement) do
    subject_index = Map.new(statement["subject"], &{&1["name"], &1})
    required = value(context, :required_provenance_subjects) || @default_subjects

    Enum.flat_map(required, fn name ->
      case Map.fetch(subject_index, name) do
        {:ok, %{"digest" => %{"sha256" => sha256}}} when is_binary(sha256) and sha256 != "" ->
          []

        {:ok, _subject} ->
          [
            finding(
              "missing_subject_digest",
              "Provenance subject is missing a sha256 digest.",
              name
            )
          ]

        :error ->
          [finding("missing_provenance_subject", "Required provenance subject is missing.", name)]
      end
    end)
  end

  defp material_findings(statement) do
    materials = statement["predicate"]["materials"]

    Enum.flat_map(@required_materials, fn {uri, _context_key, digest_key} ->
      if material_has_digest?(materials, uri, digest_key) do
        []
      else
        [missing_material(uri, digest_key)]
      end
    end)
  end

  defp material_has_digest?(materials, uri, digest_key) do
    case Enum.find(materials, &(value(&1, :uri) == uri)) do
      %{"digest" => digest} when is_map(digest) -> present?(Map.get(digest, digest_key))
      _missing -> false
    end
  end

  defp invocation_digest_findings(statement) do
    parameters = statement["predicate"]["invocation"]["parameters"]

    @required_invocation_digests
    |> Enum.reject(&present?(Map.get(parameters, Atom.to_string(&1))))
    |> Enum.map(fn key ->
      finding(
        "missing_invocation_digest",
        "Provenance invocation parameters are missing a required digest.",
        Atom.to_string(key)
      )
    end)
  end

  defp maybe_persist(_statement, findings, _context) when findings != [], do: nil

  defp maybe_persist(statement, [], context) do
    run_attempt_id = value(context, :run_attempt_id) || value(value(context, :run_attempt), :id)
    blob_root = value(context, :blob_root)

    if run_attempt_id && blob_root do
      content = Jason.encode!(statement, pretty: true)
      blob = BlobStore.write!(content, blob_root: blob_root)

      Ash.create!(
        Artifact,
        %{
          run_attempt_id: run_attempt_id,
          kind: "provenance",
          media_type: "application/vnd.in-toto+json",
          projection_path: "provenance.intoto.json",
          blob_ref: blob.ref,
          sha256: blob.sha256,
          raw_sha256: blob.sha256,
          size_bytes: blob.size_bytes,
          subject_kind: "run_attempt",
          producer: inspect(__MODULE__),
          schema_version: @schema_version,
          sensitivity: :public
        },
        domain: Factory
      )
    end
  end

  defp input_digests(context, statement) do
    %{
      "subject_count" => length(statement["subject"]),
      "material_count" => length(statement["predicate"]["materials"]),
      "run_bundle_root_sha256" => run_bundle_root_sha256(context),
      "base_commit" => material_digest(context, :base_commit),
      "container_image_digest" => material_digest(context, :container_image_digest),
      "test_pack_sha256" => material_digest(context, :test_pack_sha256),
      "policy_sha256" =>
        value(context, :policy_sha256) || value(value(context, :run_spec), :policy_sha256)
    }
  end

  defp evidence_refs(nil), do: ["provenance.intoto.json"]

  defp evidence_refs(artifact),
    do: [value(artifact, :projection_path) || "provenance.intoto.json"]

  defp missing_material(uri, digest_key) do
    finding(
      "missing_material_digest",
      "Provenance material is missing a required digest.",
      uri,
      %{"digest_key" => digest_key}
    )
  end

  defp finding(category, message, subject, extra \\ %{}) do
    %{
      "category" => category,
      "severity" => "blocking",
      "message" => message,
      "subject" => subject
    }
    |> Map.merge(extra)
  end

  defp status([]), do: :passed
  defp status(_findings), do: :failed

  defp run_bundle_root_sha256(context) do
    value(context, :run_bundle_root_sha256) ||
      value(value(context, :run_bundle), :bundle_root_sha256)
  end

  defp canonical_json(value), do: Jason.encode!(value)

  defp dedupe_by(values, key) do
    values
    |> Enum.reverse()
    |> Enum.uniq_by(&Map.get(&1, key))
    |> Enum.reverse()
  end

  defp normalize_sha("sha256:" <> digest), do: digest
  defp normalize_sha(digest), do: digest

  defp command_line(argv) when is_list(argv), do: Enum.join(argv, " ")
  defp command_line(_argv), do: nil

  defp present?(value), do: value not in [nil, ""]

  defp value(nil, _key), do: nil

  defp value(map, key) when is_map(map),
    do: Map.get(map, key, Map.get(map, Atom.to_string(key)))

  defp value(_value, _key), do: nil
end
