defmodule Conveyor.Planning.LayeredRoots do
  @moduledoc """
  Builds domain-separated authority, review, and archive root manifests.
  """

  @schema_version "conveyor.root_manifest@1"
  @digest_schema_version "conveyor.digest_ref@1"
  @subject_schema_version "conveyor.subject_ref@1"
  @canonicalization_profile "rfc8785-jcs"
  @hash_algorithm "sha256"
  @root_version 1

  @spec build(map()) :: map()
  def build(input) when is_map(input) do
    normalized = normalize_value(input)

    shared_manifest =
      root_manifest(
        "shared_authority",
        entries(normalized, :shared_authority_entries),
        omitted_subject_classes(normalized)
      )

    epic_manifests =
      normalized
      |> value(:epic_authority_entries, %{})
      |> Enum.map(fn {epic_key, entries} ->
        {to_string(epic_key),
         root_manifest("epic_authority", entries, omitted_subject_classes(normalized))}
      end)
      |> Map.new()

    review_manifest =
      root_manifest(
        "review",
        entries(normalized, :review_projection_entries),
        omitted_subject_classes(normalized)
      )

    archive_manifest =
      root_manifest(
        "archive_bundle",
        archive_entries(
          shared_manifest,
          epic_manifests,
          review_manifest,
          entries(normalized, :supporting_evidence_entries)
        ),
        omitted_subject_classes(normalized)
      )

    %{
      status: :complete,
      canonicalization_profile: @canonicalization_profile,
      hash_algorithm: @hash_algorithm,
      shared_authority_root: shared_manifest["manifest_digest"],
      shared_authority_manifest: shared_manifest,
      epic_authority_roots:
        Map.new(epic_manifests, fn {key, manifest} -> {key, manifest["manifest_digest"]} end),
      epic_authority_manifests: epic_manifests,
      review_root: review_manifest["manifest_digest"],
      review_manifest: review_manifest,
      archive_bundle_root: archive_manifest["manifest_digest"],
      archive_bundle_manifest: archive_manifest,
      excluded_approval_record_ref: approval_record_ref(normalized)
    }
  end

  defp root_manifest(root_kind, entries, omitted_subject_classes) do
    manifest_without_digest = %{
      "schema_version" => @schema_version,
      "root_kind" => root_kind,
      "root_version" => @root_version,
      "canonicalization_profile" => @canonicalization_profile,
      "hash_algorithm" => @hash_algorithm,
      "sorted_entries" => sort_entries(entries),
      "omitted_subject_classes" => Enum.sort(omitted_subject_classes)
    }

    Map.put(
      manifest_without_digest,
      "manifest_digest",
      digest_ref(domain_digest(root_kind, manifest_without_digest))
    )
  end

  defp archive_entries(
         shared_manifest,
         epic_manifests,
         review_manifest,
         supporting_evidence_entries
       ) do
    root_entries =
      [
        root_entry("shared_authority_root", "shared", shared_manifest),
        root_entry("review_root", "review", review_manifest)
      ] ++
        Enum.map(epic_manifests, fn {epic_key, manifest} ->
          root_entry("epic_authority_root", epic_key, manifest)
        end)

    root_entries ++ supporting_evidence_entries
  end

  defp root_entry(subject_class, id_or_key, manifest) do
    %{
      "subject_class" => subject_class,
      "ref" => %{
        "schema_version" => @subject_schema_version,
        "kind" => subject_class,
        "id_or_key" => id_or_key,
        "digest" => manifest["manifest_digest"]
      }
    }
  end

  defp entries(input, key), do: value(input, key, [])

  defp omitted_subject_classes(input) do
    if approval_record_ref(input), do: ["approval_record"], else: []
  end

  defp approval_record_ref(input) do
    input
    |> value(:approval_record_ref)
    |> case do
      nil -> nil
      %{"ref" => ref} -> ref
      ref -> ref
    end
  end

  defp sort_entries(entries) when is_list(entries) do
    entries
    |> Enum.reject(&approval_record_entry?/1)
    |> Enum.map(&normalize_entry/1)
    |> Enum.sort_by(fn entry ->
      ref = entry["ref"]
      {entry["subject_class"], ref["kind"], ref["id_or_key"], digest_value(ref["digest"])}
    end)
  end

  defp approval_record_entry?(entry) do
    value(entry, :subject_class) == "approval_record" or
      entry |> value(:ref, %{}) |> value(:kind) == "approval_record"
  end

  defp normalize_entry(entry) do
    entry = stringify_map(entry)

    %{
      "subject_class" => entry["subject_class"],
      "ref" => normalize_subject_ref(entry["ref"])
    }
  end

  defp normalize_subject_ref(ref) do
    ref
    |> stringify_map()
    |> Map.put_new("schema_version", @subject_schema_version)
  end

  defp digest_ref(value) do
    %{
      "schema_version" => @digest_schema_version,
      "algorithm" => @hash_algorithm,
      "value" => value
    }
  end

  defp domain_digest(root_kind, manifest_without_digest) do
    bytes = "conveyor:#{root_kind}:v#{@root_version}\0" <> canonical_json(manifest_without_digest)
    :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
  end

  defp canonical_json(%{} = map) do
    entries =
      map
      |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
      |> Enum.map(fn {key, nested} ->
        Jason.encode!(to_string(key)) <> ":" <> canonical_json(nested)
      end)

    "{" <> Enum.join(entries, ",") <> "}"
  end

  defp canonical_json(values) when is_list(values),
    do: "[" <> Enum.map_join(values, ",", &canonical_json/1) <> "]"

  defp canonical_json(value) when is_atom(value), do: value |> Atom.to_string() |> Jason.encode!()
  defp canonical_json(value), do: Jason.encode!(value)

  defp digest_value(%{} = digest), do: value(digest, :value, "")
  defp digest_value(value), do: to_string(value)

  defp normalize_value(%{} = map),
    do: Map.new(map, fn {key, value} -> {key, normalize_value(value)} end)

  defp normalize_value(values) when is_list(values), do: Enum.map(values, &normalize_value/1)
  defp normalize_value(value), do: value

  defp stringify_map(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), stringify_value(value)} end)
  end

  defp stringify_value(value) when is_map(value), do: stringify_map(value)
  defp stringify_value(values) when is_list(values), do: Enum.map(values, &stringify_value/1)
  defp stringify_value(value) when is_atom(value), do: Atom.to_string(value)
  defp stringify_value(value), do: value

  defp value(map, key, default \\ nil) do
    Map.get(map, key, Map.get(map, to_string(key), default))
  end
end
