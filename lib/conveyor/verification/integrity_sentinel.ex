defmodule Conveyor.Verification.IntegritySentinel do
  @moduledoc """
  Deterministic Test-Integrity Sentinel probe evaluator.

  The Sentinel records whether test evidence is trustworthy enough to support
  verification obligations. It does not satisfy obligations directly and does
  not turn quarantine into authority.
  """

  @default_probes [
    :base_calibration,
    :falsifier_survival,
    :hermeticity,
    :repeatability,
    :mapping,
    :mount_boundary,
    :required_artifacts,
    :source_mutation,
    :hidden_dependency,
    :falsifier_preservation
  ]

  @hermetic_controls %{
    network: :blocked,
    clock: :controlled,
    rng: :seeded,
    ordering: :stable,
    locale: :pinned,
    shared_state: :isolated
  }

  @spec run(map(), map(), keyword()) :: map()
  def run(spec, observations, opts \\ [])
      when is_map(spec) and is_map(observations) and is_list(opts) do
    probes = Keyword.get(opts, :required_probes, @default_probes)

    probe_results =
      probes
      |> Enum.map(&normalize_probe/1)
      |> Map.new(fn probe ->
        {probe, evaluate_probe(probe, value(observations, probe))}
      end)

    test_integrity_run =
      %{
        "schema_version" => "conveyor.test_integrity_run@1",
        "test_pack_id" => required_string(spec, :test_pack_id),
        "integrity_spec_digest" => required_string(spec, :integrity_spec_digest),
        "sample_no" => required_integer(spec, :sample_no),
        "slice_id" => required_string(spec, :slice_id),
        "run_spec_id" => optional_string(spec, :run_spec_id),
        "probe_results" => probe_results,
        "findings" => findings(probe_results),
        "verdict" => verdict(probe_results),
        "evaluated_at" => Keyword.fetch!(opts, :evaluated_at)
      }

    digest = "sha256:#{digest(test_integrity_run)}"

    test_integrity_run
    |> Map.put("integrity_run_digest", digest)
    |> Map.put("id", "test_integrity_run:#{digest}")
  end

  defp normalize_probe(probe) when is_atom(probe), do: Atom.to_string(probe)
  defp normalize_probe(probe) when is_binary(probe), do: probe

  defp evaluate_probe(_probe, nil), do: not_assessed()

  defp evaluate_probe("base_calibration", observation) do
    cond do
      value(observation, :expected_role) != value(observation, :observed_role) ->
        failed("test_integrity.base_calibration_role_mismatch", "base_calibration")

      value(observation, :base_behavior) not in ["red_on_stub", "falsifier_failed_on_base"] ->
        failed("test_integrity.base_calibration_missing_red_signal", "base_calibration")

      true ->
        passed()
    end
  end

  defp evaluate_probe("falsifier_survival", observation) do
    cond do
      value(observation, :required) == false ->
        passed()

      value(observation, :survived) == true ->
        passed()

      present?(value(observation, :superseded_by)) ->
        passed()

      true ->
        failed("test_integrity.falsifier_did_not_survive", "falsifier_survival")
    end
  end

  defp evaluate_probe("hermeticity", observation) do
    findings =
      @hermetic_controls
      |> Enum.reject(fn {control, expected} -> value(observation, control) == expected end)
      |> Enum.map(fn {control, _expected} ->
        finding("test_integrity.non_hermetic_#{control}", Atom.to_string(control))
      end)

    if findings == [], do: passed(), else: failed(findings)
  end

  defp evaluate_probe("repeatability", observation) do
    result_digests = value(observation, :result_digests) || []
    failure_signatures = value(observation, :failure_signatures) || []

    cond do
      value(observation, :sample_count) in [nil, 0, 1] ->
        not_assessed()

      unstable?(result_digests) or unstable?(failure_signatures) ->
        suspect("test_integrity.repeatability_unstable", "repeatability")

      true ->
        passed()
    end
  end

  defp evaluate_probe("mapping", observation) do
    refs = value(observation, :obligation_refs) || []

    if refs != [] and Enum.all?(refs, &mapped_obligation?/1) do
      passed()
    else
      failed("test_integrity.obligation_mapping_missing", "mapping")
    end
  end

  defp evaluate_probe("mount_boundary", observation) do
    case value(observation, :write_violations) || [] do
      [] -> passed()
      paths -> failed("test_integrity.mount_write_boundary_violation", Enum.join(paths, ","))
    end
  end

  defp evaluate_probe("required_artifacts", observation) do
    required = value(observation, :required) || []
    present = MapSet.new(value(observation, :present) || [])
    missing = Enum.reject(required, &MapSet.member?(present, &1))

    if missing == [] do
      passed()
    else
      failed("test_integrity.required_artifact_missing", Enum.join(missing, ","))
    end
  end

  defp evaluate_probe("source_mutation", observation) do
    case value(observation, :mutated_production_paths) || [] do
      [] -> passed()
      paths -> failed("test_integrity.production_source_mutated", Enum.join(paths, ","))
    end
  end

  defp evaluate_probe("hidden_dependency", observation) do
    secret_refs = value(observation, :secret_refs) || []
    network_hosts = value(observation, :network_hosts) || []

    findings =
      []
      |> maybe_add(
        secret_refs != [],
        "test_integrity.hidden_secret_dependency",
        Enum.join(secret_refs, ",")
      )
      |> maybe_add(
        network_hosts != [],
        "test_integrity.hidden_network_dependency",
        Enum.join(network_hosts, ",")
      )

    if findings == [], do: passed(), else: failed(findings)
  end

  defp evaluate_probe("falsifier_preservation", observation) do
    dropped = value(observation, :dropped_falsifier_refs) || []
    superseded = MapSet.new(value(observation, :superseded_falsifier_refs) || [])
    unsuperseded = Enum.reject(dropped, &MapSet.member?(superseded, &1))

    if unsuperseded == [] do
      passed()
    else
      failed("test_integrity.falsifier_dropped", Enum.join(unsuperseded, ","))
    end
  end

  defp evaluate_probe(probe, _observation),
    do: failed("test_integrity.unknown_probe", probe)

  defp mapped_obligation?(ref) do
    present?(value(ref, :obligation_id)) and present?(value(ref, :acceptance_ref)) and
      present?(value(ref, :interface_oracle_ref))
  end

  defp unstable?([]), do: false
  defp unstable?(values), do: values |> Enum.uniq() |> length() > 1

  defp verdict(probe_results) do
    statuses = probe_results |> Map.values() |> Enum.map(& &1["status"])

    cond do
      Enum.any?(statuses, &(&1 == "failed")) -> "untrustworthy"
      Enum.any?(statuses, &(&1 == "suspect")) -> "suspect"
      Enum.any?(statuses, &(&1 == "not_assessed")) -> "not_assessed"
      true -> "trustworthy"
    end
  end

  defp findings(probe_results) do
    probe_results
    |> Map.values()
    |> Enum.flat_map(& &1["findings"])
  end

  defp passed, do: %{"status" => "passed", "findings" => []}
  defp not_assessed, do: %{"status" => "not_assessed", "findings" => []}

  defp suspect(rule_key, anchor),
    do: %{"status" => "suspect", "findings" => [finding(rule_key, anchor)]}

  defp failed(rule_key, anchor), do: failed([finding(rule_key, anchor)])
  defp failed(findings), do: %{"status" => "failed", "findings" => findings}

  defp finding(rule_key, anchor) do
    %{
      "rule_key" => rule_key,
      "anchor" => anchor,
      "severity" => "blocking"
    }
  end

  defp maybe_add(findings, true, rule_key, anchor), do: [finding(rule_key, anchor) | findings]
  defp maybe_add(findings, false, _rule_key, _anchor), do: findings

  defp required_string(attrs, key) do
    case value(attrs, key) do
      value when is_atom(value) and not is_nil(value) -> Atom.to_string(value)
      value when is_binary(value) and value != "" -> value
      _other -> raise ArgumentError, "#{key} must be present"
    end
  end

  defp optional_string(attrs, key) do
    case value(attrs, key) do
      nil -> nil
      value when is_atom(value) and not is_nil(value) -> Atom.to_string(value)
      value when is_binary(value) and value != "" -> value
      _other -> raise ArgumentError, "#{key} must be a non-empty string when present"
    end
  end

  defp required_integer(attrs, key) do
    case value(attrs, key) do
      value when is_integer(value) and value > 0 -> value
      _other -> raise ArgumentError, "#{key} must be a positive integer"
    end
  end

  defp present?(value) when is_binary(value), do: value != ""
  defp present?(value) when is_atom(value), do: not is_nil(value)
  defp present?(_value), do: false

  defp digest(value) do
    value
    |> canonical()
    |> Jason.encode!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp canonical(map) when is_map(map) do
    map
    |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
    |> Map.new(fn {key, value} -> {key, canonical(value)} end)
  end

  defp canonical(values) when is_list(values), do: Enum.map(values, &canonical/1)
  defp canonical(value), do: value

  defp value(map, key) when is_map(map) do
    atom_key = atom_key(key)

    cond do
      Map.has_key?(map, key) -> Map.get(map, key)
      Map.has_key?(map, to_string(key)) -> Map.get(map, to_string(key))
      not is_nil(atom_key) and Map.has_key?(map, atom_key) -> Map.get(map, atom_key)
      true -> nil
    end
  end

  defp value(_other, _key), do: nil

  defp atom_key(key) when is_atom(key), do: key

  defp atom_key(key) when is_binary(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> nil
  end
end
