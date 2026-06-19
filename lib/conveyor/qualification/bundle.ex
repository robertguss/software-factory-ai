defmodule Conveyor.Qualification.Bundle do
  @moduledoc """
  Offline-verifiable qualification bundle projection and verifier.

  Verification is intentionally pure: it only checks fields carried in the
  bundle and never consults the live database.
  """

  @schema_version "conveyor.qualification_bundle@1"

  @spec build(map()) :: map()
  def build(input) when is_map(input) do
    grant = stringify_map(value(input, :grant, %{}))
    scope_lattice = stringify_map(value(input, :scope_lattice, %{}))

    %{
      "schema_version" => @schema_version,
      "offline_verifiable?" => true,
      "grant_id" => value(grant, :id),
      "registry_digest" => value(input, :registry_digest),
      "canonicalization_profile" => value(input, :canonicalization_profile, "rfc8785-jcs"),
      "scope_digest" => value(grant, :scope_digest),
      "scope_lattice_digest" => value(scope_lattice, :scope_digest),
      "evidence_root_digest" => value(grant, :evidence_root_digest),
      "root_manifest_digest" => value(input, :root_manifest_digest),
      "run_digest" => value(input, :run_digest),
      "hard_invariant_verdicts" => value(input, :hard_invariant_verdicts, []),
      "canary_refs" => value(input, :canary_refs, []),
      "replay_anchors" => value(input, :replay_anchors, []),
      "waiver_refs" => value(grant, :waiver_refs, []),
      "waiver_availability" => value(input, :waiver_availability, []),
      "signature_status" => value(input, :signature_status, "unsigned_local")
    }
  end

  @spec verify_offline(map()) :: {:ok, map()} | {:error, map()}
  def verify_offline(bundle) when is_map(bundle) do
    bundle = stringify_map(bundle)

    with :ok <-
           require_equal(
             bundle["scope_digest"],
             bundle["scope_lattice_digest"],
             :scope_digest_mismatch
           ),
         :ok <- require_digest(bundle["registry_digest"], :registry_digest_missing),
         :ok <- require_digest(bundle["evidence_root_digest"], :evidence_root_missing),
         :ok <- require_digest(bundle["root_manifest_digest"], :root_manifest_digest_missing),
         :ok <- require_digest(bundle["run_digest"], :run_digest_missing),
         :ok <- require_all_passed(bundle["hard_invariant_verdicts"]),
         :ok <- require_non_empty(bundle["canary_refs"], :canary_refs_missing),
         :ok <- require_non_empty(bundle["replay_anchors"], :replay_anchors_missing),
         :ok <- require_waivers_available(bundle["waiver_refs"], bundle["waiver_availability"]),
         :ok <- require_present(bundle["signature_status"], :signature_status_missing) do
      {:ok,
       %{
         "schema_version" => "conveyor.qualification_bundle_verification@1",
         "grant_id" => bundle["grant_id"],
         "checked_without_live_db?" => true,
         "status" => "verified"
       }}
    end
  end

  defp require_equal(left, right, reason) do
    if present?(left) and left == right, do: :ok, else: {:error, %{reason: reason}}
  end

  defp require_digest(value, reason) do
    if is_binary(value) and String.match?(value, ~r/^sha256:[0-9a-f]{64}$/) do
      :ok
    else
      {:error, %{reason: reason}}
    end
  end

  defp require_all_passed(verdicts) when is_list(verdicts) and verdicts != [] do
    failed =
      Enum.find(verdicts, fn verdict ->
        value(verdict, :status) not in ["passed", :passed, true]
      end)

    if failed do
      {:error, %{reason: :hard_invariant_failed, verdict: failed}}
    else
      :ok
    end
  end

  defp require_all_passed(_verdicts), do: {:error, %{reason: :hard_invariant_verdicts_missing}}

  defp require_non_empty(values, _reason) when is_list(values) and values != [], do: :ok
  defp require_non_empty(_values, reason), do: {:error, %{reason: reason}}

  defp require_waivers_available(waiver_refs, availability) do
    # verify_offline accepts externally-supplied bundles; tolerate a missing/non-list
    # availability (no waivers available) and missing waiver_refs (nothing to require)
    # instead of crashing with FunctionClauseError.
    waiver_refs = List.wrap(waiver_refs)
    availability = if is_list(availability), do: availability, else: []
    by_ref = Map.new(availability, fn item -> {value(item, :waiver_ref), item} end)

    missing =
      Enum.find(waiver_refs, fn waiver_ref ->
        value(Map.get(by_ref, waiver_ref, %{}), :available) != true
      end)

    if missing, do: {:error, %{reason: :waiver_unavailable, waiver_ref: missing}}, else: :ok
  end

  defp require_present(value, reason) do
    if present?(value), do: :ok, else: {:error, %{reason: reason}}
  end

  defp present?(value), do: value not in [nil, ""]

  defp stringify_map(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), stringify_value(value)} end)
  end

  defp stringify_value(value) when is_map(value), do: stringify_map(value)
  defp stringify_value(values) when is_list(values), do: Enum.map(values, &stringify_value/1)
  defp stringify_value(value) when is_boolean(value), do: value
  defp stringify_value(value) when is_atom(value), do: Atom.to_string(value)
  defp stringify_value(value), do: value

  defp value(map, key, default \\ nil) do
    Map.get(map, key, Map.get(map, to_string(key), default))
  end
end
