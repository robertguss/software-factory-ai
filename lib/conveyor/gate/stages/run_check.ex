defmodule Conveyor.Gate.Stages.RunCheck do
  @moduledoc """
  Gate stage 11: validates run artifact schemas, digests, and consistency.
  """

  @behaviour Conveyor.Gate.Stage

  alias Conveyor.Artifacts.BlobStore
  alias Conveyor.Gate.StageResult

  @run_bundle_schema "conveyor.run_bundle@1"
  @supported_schema_versions MapSet.new([
                               @run_bundle_schema,
                               "conveyor.evidence_packet@1",
                               "conveyor.verification_log@1",
                               "conveyor.review@1",
                               "conveyor.gate_result@1",
                               "conveyor.provenance@1",
                               "conveyor.artifact@1"
                             ])

  @required_artifact_paths ["dossier.md", "logs/verification.json"]
  @injection_markers [
    "ignore previous instructions",
    "ignore the locked contract",
    "ignored the locked contract",
    "followed untrusted instructions",
    "bypassed contract",
    "override the contract"
  ]

  @impl true
  def run(context, _opts \\ []) do
    artifacts = value(context, :artifacts) || []
    contents = contents_by_path(value(context, :artifact_contents) || [])
    manifest = manifest(context, contents)
    findings = findings(context, artifacts, contents, manifest)

    %StageResult{
      key: "run_check",
      status: status(findings),
      required?: true,
      findings: findings,
      evidence_refs: evidence_refs(artifacts, manifest),
      input_digests: %{
        "artifact_count" => length(artifacts),
        "manifest_sha256" => manifest_sha256(manifest)
      }
    }
  end

  defp findings(context, artifacts, contents, manifest) do
    []
    |> Kernel.++(required_artifact_findings(context, artifacts, contents, manifest))
    |> Kernel.++(artifact_schema_findings(artifacts, contents))
    |> Kernel.++(artifact_digest_findings(artifacts, contents))
    |> Kernel.++(manifest_findings(value(context, :run_bundle), manifest, artifacts))
    |> Kernel.++(prompt_injection_findings(contents))
  end

  defp required_artifact_findings(context, artifacts, contents, manifest) do
    paths = artifact_paths(artifacts, contents)
    required_paths = value(context, :required_artifact_paths) || @required_artifact_paths

    artifact_findings =
      required_paths
      |> Enum.reject(&(&1 in paths))
      |> Enum.map(fn path ->
        finding("missing_required_artifact", "Required gate artifact is missing.", path)
      end)

    if is_nil(manifest) do
      [
        finding("missing_manifest", "RunBundle manifest is required.", "manifest.json")
        | artifact_findings
      ]
    else
      artifact_findings
    end
  end

  defp artifact_schema_findings(artifacts, contents) do
    artifact_findings =
      artifacts
      |> Enum.map(&{path_for(&1), value(&1, :schema_version)})
      |> Enum.filter(fn {_path, schema_version} ->
        not MapSet.member?(@supported_schema_versions, schema_version)
      end)
      |> Enum.map(fn {path, schema_version} ->
        finding(
          "unsupported_schema_version",
          "Artifact schema_version is unsupported.",
          path,
          %{"schema_version" => schema_version}
        )
      end)

    content_findings =
      contents
      |> Enum.flat_map(fn {path, content} -> content_schema_findings(path, content) end)

    artifact_findings ++ content_findings
  end

  defp content_schema_findings(path, content) do
    case decode_json(content) do
      {:ok, %{"schema_version" => schema_version}} ->
        schema_version_findings(path, schema_version)

      {:ok, _json_without_schema} ->
        [
          finding(
            "schema_validation_failed",
            "JSON artifact content is missing schema_version.",
            path
          )
        ]

      :not_json ->
        []
    end
  end

  defp schema_version_findings(path, schema_version) do
    if MapSet.member?(@supported_schema_versions, schema_version) do
      []
    else
      [
        finding(
          "unsupported_schema_version",
          "Artifact content schema_version is unsupported.",
          path,
          %{"schema_version" => schema_version}
        )
      ]
    end
  end

  defp artifact_digest_findings(artifacts, contents) do
    artifacts
    |> Enum.flat_map(fn artifact ->
      path = path_for(artifact)

      contents
      |> Map.fetch(path)
      |> artifact_digest_finding(path, artifact)
    end)
  end

  defp artifact_digest_finding({:ok, content}, path, artifact) do
    actual = BlobStore.sha256(content)
    expected = raw_sha256(value(artifact, :sha256))

    if actual == expected do
      []
    else
      [
        finding(
          "artifact_hash_mismatch",
          "Artifact content hash does not match metadata.",
          path,
          %{"expected_sha256" => expected, "actual_sha256" => actual}
        )
      ]
    end
  end

  defp artifact_digest_finding(:error, _path, _artifact), do: []

  defp manifest_findings(nil, nil, _artifacts), do: []

  defp manifest_findings(run_bundle, manifest, artifacts) do
    []
    |> Kernel.++(manifest_schema_findings(run_bundle, manifest))
    |> Kernel.++(manifest_digest_findings(run_bundle, manifest))
    |> Kernel.++(manifest_entry_findings(manifest, artifacts))
  end

  defp manifest_schema_findings(_run_bundle, nil), do: []

  defp manifest_schema_findings(run_bundle, manifest) do
    schema_version = manifest["schema_version"]

    []
    |> maybe_add(
      schema_version != @run_bundle_schema,
      "unsupported_schema_version",
      "RunBundle manifest schema_version is unsupported.",
      "manifest.json",
      %{"schema_version" => schema_version}
    )
    |> maybe_add(
      value(run_bundle, :schema_version) not in [nil, @run_bundle_schema],
      "unsupported_schema_version",
      "RunBundle record schema_version is unsupported.",
      value(run_bundle, :manifest_ref),
      %{"schema_version" => value(run_bundle, :schema_version)}
    )
  end

  defp manifest_digest_findings(_run_bundle, nil), do: []

  defp manifest_digest_findings(run_bundle, manifest) do
    expected_manifest_sha256 = value(run_bundle, :manifest_sha256)
    actual_manifest_sha256 = manifest_sha256(manifest)
    expected_root = value(run_bundle, :bundle_root_sha256)
    actual_root = bundle_root_sha256(manifest["entries"] || [])

    []
    |> maybe_add(
      expected_manifest_sha256 && expected_manifest_sha256 != actual_manifest_sha256,
      "manifest_hash_mismatch",
      "RunBundle manifest hash does not match manifest bytes.",
      "manifest.json",
      %{"expected_sha256" => expected_manifest_sha256, "actual_sha256" => actual_manifest_sha256}
    )
    |> maybe_add(
      manifest["bundle_root_sha256"] != actual_root or
        (expected_root && expected_root != actual_root),
      "bundle_root_mismatch",
      "RunBundle root digest does not match manifest entries.",
      "manifest.json",
      %{
        "expected_sha256" => expected_root || manifest["bundle_root_sha256"],
        "actual_sha256" => actual_root
      }
    )
  end

  defp manifest_entry_findings(nil, _artifacts), do: []

  defp manifest_entry_findings(manifest, artifacts) do
    artifact_index = Map.new(artifacts, &{path_for(&1), &1})

    manifest
    |> Map.get("entries", [])
    |> Enum.flat_map(fn entry ->
      path = entry["path"]

      case Map.fetch(artifact_index, path) do
        {:ok, artifact} ->
          manifest_entry_mismatch_findings(entry, artifact)

        :error ->
          [
            finding(
              "manifest_entry_missing_artifact",
              "Manifest entry has no matching Artifact.",
              path
            )
          ]
      end
    end)
  end

  defp manifest_entry_mismatch_findings(entry, artifact) do
    path = entry["path"]

    []
    |> maybe_add(
      raw_sha256(value(artifact, :sha256)) != entry["sha256"],
      "manifest_entry_hash_mismatch",
      "Manifest entry hash does not match Artifact metadata.",
      path
    )
    |> maybe_add(
      value(artifact, :size_bytes) != entry["size_bytes"],
      "manifest_entry_size_mismatch",
      "Manifest entry size does not match Artifact metadata.",
      path
    )
    |> maybe_add(
      value(artifact, :schema_version) != entry["schema_version"],
      "manifest_entry_schema_mismatch",
      "Manifest entry schema_version does not match Artifact metadata.",
      path
    )
  end

  defp prompt_injection_findings(contents) do
    contents
    |> Enum.filter(fn {_path, content} -> follows_untrusted_instruction?(content) end)
    |> Enum.map(fn {path, _content} ->
      finding(
        "untrusted_instruction_followed",
        "Artifact output appears to follow untrusted instructions over the locked contract.",
        path
      )
    end)
  end

  defp follows_untrusted_instruction?(content) do
    downcased = String.downcase(content)
    Enum.any?(@injection_markers, &String.contains?(downcased, &1))
  end

  defp manifest(context, contents) do
    value(context, :manifest) || decoded_manifest(contents)
  end

  defp decoded_manifest(contents) do
    case Map.fetch(contents, "manifest.json") do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, manifest} -> manifest
          {:error, _error} -> nil
        end

      :error ->
        nil
    end
  end

  defp contents_by_path(contents) do
    Map.new(contents, fn content ->
      path = value(content, :projection_path) || value(content, :source) || value(content, :path)
      {path, value(content, :content) || ""}
    end)
  end

  defp artifact_paths(artifacts, contents) do
    artifacts
    |> Enum.map(&path_for/1)
    |> Kernel.++(Map.keys(contents))
    |> Enum.uniq()
  end

  defp evidence_refs(artifacts, manifest) do
    artifacts
    |> Enum.map(&path_for/1)
    |> Kernel.++(if manifest, do: ["manifest.json"], else: [])
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp path_for(artifact), do: value(artifact, :projection_path) || value(artifact, :path)

  defp finding(category, message, path, extra \\ %{}) do
    %{
      "category" => category,
      "severity" => "blocking",
      "message" => message,
      "path" => path
    }
    |> Map.merge(extra)
  end

  defp maybe_add(findings, condition, category, message, path, extra \\ %{})

  defp maybe_add(findings, true, category, message, path, extra),
    do: [finding(category, message, path, extra) | findings]

  defp maybe_add(findings, false, _category, _message, _path, _extra), do: findings
  defp maybe_add(findings, nil, _category, _message, _path, _extra), do: findings

  defp status([]), do: :passed
  defp status(_findings), do: :failed

  defp manifest_sha256(nil), do: nil

  defp manifest_sha256(manifest) do
    manifest
    |> canonical_json()
    |> BlobStore.sha256()
  end

  defp bundle_root_sha256(entries) do
    entries
    |> Enum.map(
      &Map.take(&1, ["path", "kind", "sha256", "size_bytes", "sensitivity", "schema_version"])
    )
    |> canonical_json()
    |> BlobStore.sha256()
  end

  defp decode_json(content) do
    trimmed = String.trim_leading(content)

    if String.starts_with?(trimmed, "{") do
      case Jason.decode(content) do
        {:ok, decoded} -> {:ok, decoded}
        {:error, _error} -> {:ok, %{}}
      end
    else
      :not_json
    end
  end

  defp canonical_json(value) when is_map(value) do
    body =
      value
      |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
      |> Enum.map(fn {key, nested} ->
        Jason.encode!(to_string(key)) <> ":" <> canonical_json(nested)
      end)
      |> Enum.join(",")

    "{" <> body <> "}"
  end

  defp canonical_json(value) when is_list(value),
    do: "[" <> Enum.map_join(value, ",", &canonical_json/1) <> "]"

  defp canonical_json(value), do: Jason.encode!(value)

  defp raw_sha256("sha256:" <> digest), do: raw_sha256(digest)
  defp raw_sha256(digest), do: digest

  defp value(nil, _key), do: nil

  defp value(map, key) when is_map(map),
    do: Map.get(map, key) || Map.get(map, Atom.to_string(key))
end
