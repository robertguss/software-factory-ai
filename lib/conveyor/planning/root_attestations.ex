defmodule Conveyor.Planning.RootAttestations do
  @moduledoc """
  Emits canonical in-toto statements over planning roots and evidence.
  """

  @schema_version "conveyor.attestation_statement@1"
  @statement_type "https://in-toto.io/Statement/v1"
  @predicate_type "https://conveyor.dev/attestations/planning-roots/v1"
  @predicate_schema_version "conveyor.planning_root_attestation_predicate@1"

  @spec build(map()) :: map()
  def build(input) when is_map(input) do
    roots = value(input, :layered_roots, %{})
    statement = statement(input, roots)

    %{
      status: :complete,
      statement_digest: digest(statement),
      statements: [statement]
    }
  end

  defp statement(input, roots) do
    %{
      "schema_version" => @schema_version,
      "_type" => @statement_type,
      "subject" => subjects(roots, value(input, :supporting_evidence_entries, [])),
      "predicateType" => @predicate_type,
      "predicate" => predicate(input, roots),
      "signature_status" => value(input, :signature_status, "unsigned")
    }
    |> put_optional("verification_bundle_ref", value(input, :verification_bundle_ref))
    |> put_optional("signer_identity", value(input, :signer_identity))
  end

  defp subjects(roots, supporting_evidence_entries) do
    roots
    |> root_subjects()
    |> Kernel.++(evidence_subjects(supporting_evidence_entries))
    |> Enum.sort_by(& &1["name"])
  end

  defp root_subjects(roots) do
    epic_roots =
      roots
      |> value(:epic_authority_roots, %{})
      |> Enum.map(fn {epic_key, digest_ref} ->
        subject("conveyor:root/epic_authority/#{epic_key}", digest_ref)
      end)

    [
      subject("conveyor:root/shared_authority", value(roots, :shared_authority_root)),
      subject("conveyor:root/review", value(roots, :review_root)),
      subject("conveyor:root/archive_bundle", value(roots, :archive_bundle_root))
    ] ++ epic_roots
  end

  defp evidence_subjects(entries) do
    entries
    |> Enum.map(fn entry ->
      ref = value(entry, :ref, %{})

      subject(
        "conveyor:evidence/#{value(ref, :kind)}/#{value(ref, :id_or_key)}",
        value(ref, :digest)
      )
    end)
    |> Enum.sort_by(& &1["name"])
  end

  defp subject(name, digest_ref) do
    %{
      "name" => name,
      "digest" => %{digest_algorithm(digest_ref) => digest_value(digest_ref)}
    }
  end

  defp predicate(input, roots) do
    %{
      "schema_version" => @predicate_schema_version,
      "planning_run_id" => value(input, :planning_run_id),
      "canonicalization_profile" => value(roots, :canonicalization_profile, "rfc8785-jcs"),
      "hash_algorithm" => value(roots, :hash_algorithm, "sha256"),
      "root_manifest_digests" => %{
        "shared_authority" => value(roots, :shared_authority_root),
        "epic_authority" => value(roots, :epic_authority_roots, %{}),
        "review" => value(roots, :review_root),
        "archive_bundle" => value(roots, :archive_bundle_root)
      },
      "supporting_evidence_subjects" =>
        evidence_subjects(value(input, :supporting_evidence_entries, []))
    }
  end

  defp digest(value) do
    "sha256:" <>
      (value
       |> canonical_json()
       |> then(&:crypto.hash(:sha256, &1))
       |> Base.encode16(case: :lower))
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

  defp digest_algorithm(%{} = digest_ref), do: value(digest_ref, :algorithm, "sha256")
  defp digest_algorithm(_digest), do: "sha256"

  defp digest_value(%{} = digest_ref), do: value(digest_ref, :value)
  defp digest_value("sha256:" <> value), do: value
  defp digest_value(value), do: value

  defp put_optional(map, _key, nil), do: map
  defp put_optional(map, key, value), do: Map.put(map, key, value)

  defp value(nil, _key, default), do: default

  defp value(map, key, default) when is_map(map),
    do: Map.get(map, key, Map.get(map, to_string(key), default))

  defp value(_value, _key, default), do: default

  defp value(map, key), do: value(map, key, nil)
end
