defmodule Conveyor.Verification do
  @moduledoc """
  Artifact-shaped VerificationObligation, VerificationEvidence, and
  VerificationWaiver builders.

  These resources are the authority-bearing verification primitives. They stay
  independent of TestPack aggregate status so later readiness checks can
  evaluate each obligation from explicit evidence and waiver state.
  """

  @obligation_kinds ~w(example property interface differential metamorphic policy human_judgment)
  @obligation_statuses ~w(open satisfied blocked waived superseded)

  @evidence_kinds ~w(specification calibration harness_validation candidate_result hermeticity repeatability adversarial_challenge mutation_assessment human_observation environment_attestation)
  @validity_states ~w(valid suspect invalid expired)

  @evidence_dimensions ~w(specification_present base_calibration harness_validity candidate_result hermeticity repeatability adversarial_challenge mutation_assessment human_observation environment_freshness)
  @dimension_evidence_kinds %{
    "specification_present" => "specification",
    "base_calibration" => "calibration",
    "harness_validity" => "harness_validation",
    "candidate_result" => "candidate_result",
    "hermeticity" => "hermeticity",
    "repeatability" => "repeatability",
    "adversarial_challenge" => "adversarial_challenge",
    "mutation_assessment" => "mutation_assessment",
    "human_observation" => "human_observation",
    "environment_freshness" => "environment_attestation"
  }

  @waiver_statuses ~w(active expired revoked superseded)
  @quarantine_reasons ~w(flaky non_hermetic vacuous order_dependent infrastructure_sensitive)
  @quarantine_statuses ~w(quarantined rehabilitated retired)
  @quarantine_exclusions ~w(advisory ordinary_execution both)

  @spec obligation_kinds() :: [String.t()]
  def obligation_kinds, do: @obligation_kinds

  @spec evidence_kinds() :: [String.t()]
  def evidence_kinds, do: @evidence_kinds

  @spec evidence_dimensions() :: [String.t()]
  def evidence_dimensions, do: @evidence_dimensions

  @spec validity_states() :: [String.t()]
  def validity_states, do: @validity_states

  @spec waiver_statuses() :: [String.t()]
  def waiver_statuses, do: @waiver_statuses

  @spec quarantine_reasons() :: [String.t()]
  def quarantine_reasons, do: @quarantine_reasons

  @spec new_obligation!(map()) :: map()
  def new_obligation!(attrs) when is_map(attrs) do
    obligation =
      %{
        "schema_version" => "conveyor.verification_obligation@1",
        "slice_id" => required_string(attrs, :slice_id),
        "acceptance_ref" => required_string(attrs, :acceptance_ref),
        "obligation_kind" => required_enum(attrs, :obligation_kind, @obligation_kinds),
        "required" => required_boolean(attrs, :required),
        "oracle_definition_ref" => required_string(attrs, :oracle_definition_ref),
        "evidence_requirement_ref" => required_string(attrs, :evidence_requirement_ref),
        "status" => required_enum(attrs, :status, @obligation_statuses)
      }

    Map.put(obligation, "id", "verification_obligation:sha256:#{digest(obligation)}")
  end

  @spec new_evidence!(map()) :: map()
  def new_evidence!(attrs) when is_map(attrs) do
    evidence =
      %{
        "schema_version" => "conveyor.verification_evidence@1",
        "verification_obligation_id" => required_string(attrs, :verification_obligation_id),
        "producer_kind" => required_string(attrs, :producer_kind),
        "producer_ref" => required_string(attrs, :producer_ref),
        "evidence_kind" => required_enum(attrs, :evidence_kind, @evidence_kinds),
        "validity" => required_enum(attrs, :validity, @validity_states),
        "environment_fingerprint_digest" =>
          optional_string(attrs, :environment_fingerprint_digest),
        "result_ref" => required_string(attrs, :result_ref),
        "evidence_digest" => required_string(attrs, :evidence_digest),
        "created_at" => required_string(attrs, :created_at)
      }

    Map.put(evidence, "id", "verification_evidence:sha256:#{digest(evidence)}")
  end

  @spec new_evidence_requirement!(map()) :: map()
  def new_evidence_requirement!(attrs) when is_map(attrs) do
    required_dimensions = required_enum_list(attrs, :required_dimensions, @evidence_dimensions)

    requirement =
      %{
        "schema_version" => "conveyor.evidence_requirement@1",
        "verification_obligation_id" => required_string(attrs, :verification_obligation_id),
        "required_dimensions" => required_dimensions,
        "dimension_predicates" => Map.new(required_dimensions, &{&1, dimension_predicate(&1)}),
        "created_at" => required_string(attrs, :created_at)
      }

    requirement_digest = "sha256:#{digest(requirement)}"

    requirement
    |> Map.put("requirement_digest", requirement_digest)
    |> Map.put("id", "evidence_requirement:#{requirement_digest}")
  end

  @spec evaluate_requirement(map(), [map()], keyword()) :: map()
  def evaluate_requirement(requirement, evidence, opts)
      when is_map(requirement) and is_list(evidence) and is_list(opts) do
    dimension_results =
      requirement
      |> Map.fetch!("required_dimensions")
      |> Map.new(fn dimension ->
        {dimension,
         evaluate_dimension(requirement, evidence, dimension, Keyword.get(opts, :quarantines, []))}
      end)

    waived? = active_waiver?(Keyword.get(opts, :waiver), requirement)
    result = satisfaction_result(dimension_results, waived?)
    dimension_results = apply_waiver(dimension_results, result)

    satisfaction =
      %{
        "schema_version" => "conveyor.obligation_satisfaction@1",
        "verification_obligation_id" => Map.fetch!(requirement, "verification_obligation_id"),
        "evidence_requirement_digest" => Map.fetch!(requirement, "requirement_digest"),
        "consumed_evidence_ids" => consumed_evidence_ids(requirement, dimension_results, result),
        "dimension_results" => dimension_results,
        "result" => result,
        "policy_decision_id" => Keyword.fetch!(opts, :policy_decision_id),
        "evaluated_at" => Keyword.fetch!(opts, :evaluated_at)
      }
      |> maybe_put_waiver(Keyword.get(opts, :waiver), result)

    Map.put(satisfaction, "satisfaction_digest", "sha256:#{digest(satisfaction)}")
  end

  @spec new_quarantine!(map()) :: map()
  def new_quarantine!(attrs) when is_map(attrs) do
    quarantine =
      %{
        "schema_version" => "conveyor.test_quarantine@1",
        "test_pack_id" => required_string(attrs, :test_pack_id),
        "test_id" => required_string(attrs, :test_id),
        "reason" => required_enum(attrs, :reason, @quarantine_reasons),
        "required_for_obligation_ids" =>
          required_string_list(attrs, :required_for_obligation_ids),
        "status" => required_enum(attrs, :status, @quarantine_statuses),
        "excluded_from" => required_enum(attrs, :excluded_from, @quarantine_exclusions),
        "human_decision_id" => optional_string(attrs, :human_decision_id),
        "evidence_ref" => required_string(attrs, :evidence_ref),
        "created_at" => required_string(attrs, :created_at)
      }

    Map.put(quarantine, "id", "test_quarantine:sha256:#{digest(quarantine)}")
  end

  @spec new_waiver!(map()) :: map()
  def new_waiver!(attrs) when is_map(attrs) do
    status = required_enum(attrs, :status, @waiver_statuses)
    validate_active_waiver!(attrs, status)

    waiver =
      %{
        "schema_version" => "conveyor.verification_waiver@1",
        "verification_obligation_id" => required_string(attrs, :verification_obligation_id),
        "human_decision_id" => required_string(attrs, :human_decision_id),
        "reason" => required_string(attrs, :reason),
        "compensating_control_refs" => required_string_list(attrs, :compensating_control_refs),
        "max_autonomy" => required_string(attrs, :max_autonomy),
        "owner" => required_string(attrs, :owner),
        "expires_at" => required_string(attrs, :expires_at),
        "status" => status
      }

    Map.put(waiver, "id", "verification_waiver:sha256:#{digest(waiver)}")
  end

  defp validate_active_waiver!(attrs, "active") do
    for key <- [:human_decision_id, :owner, :expires_at, :max_autonomy] do
      unless present?(value(attrs, key)) do
        raise ArgumentError, "active waiver requires #{key}"
      end
    end

    case value(attrs, :compensating_control_refs) do
      controls when is_list(controls) and controls != [] ->
        :ok

      _other ->
        raise ArgumentError, "active waiver requires compensating_control_refs"
    end
  end

  defp validate_active_waiver!(_attrs, _status), do: :ok

  defp dimension_predicate(dimension) do
    %{
      "evidence_kind" => Map.fetch!(@dimension_evidence_kinds, dimension),
      "validity" => "valid"
    }
  end

  defp evaluate_dimension(requirement, evidence, dimension, quarantines) do
    predicate = get_in(requirement, ["dimension_predicates", dimension])
    required_kind = Map.fetch!(predicate, "evidence_kind")

    matching =
      Enum.filter(evidence, fn evidence_item ->
        evidence_item["verification_obligation_id"] == requirement["verification_obligation_id"] and
          evidence_item["evidence_kind"] == required_kind
      end)

    {quarantined, available} =
      Enum.split_with(matching, &quarantined_evidence?(&1, quarantines, requirement))

    valid = Enum.filter(available, &(&1["validity"] == "valid"))
    quarantine_ids = quarantine_ids(quarantined, quarantines, requirement)

    cond do
      valid != [] ->
        %{
          "status" => "satisfied",
          "required_evidence_kind" => required_kind,
          "evidence_ids" => Enum.map(valid, & &1["id"])
        }
        |> with_quarantine_ids(quarantine_ids)

      quarantined != [] ->
        %{
          "status" => "blocked",
          "required_evidence_kind" => required_kind,
          "evidence_ids" => Enum.map(quarantined, & &1["id"]),
          "blocking_validities" => ["quarantined"],
          "quarantine_ids" => quarantine_ids
        }

      available != [] ->
        %{
          "status" => "blocked",
          "required_evidence_kind" => required_kind,
          "evidence_ids" => Enum.map(available, & &1["id"]),
          "blocking_validities" => available |> Enum.map(& &1["validity"]) |> Enum.uniq()
        }
        |> with_quarantine_ids(quarantine_ids)

      true ->
        %{
          "status" => "missing",
          "required_evidence_kind" => required_kind,
          "evidence_ids" => []
        }
        |> with_quarantine_ids(quarantine_ids)
    end
  end

  defp with_quarantine_ids(result, []), do: result

  defp with_quarantine_ids(result, quarantine_ids),
    do: Map.put(result, "quarantine_ids", quarantine_ids)

  defp quarantined_evidence?(evidence, quarantines, requirement) do
    Enum.any?(quarantines, &quarantine_matches?(&1, evidence, requirement))
  end

  defp quarantine_ids(evidence, quarantines, requirement) do
    evidence
    |> Enum.flat_map(fn evidence_item ->
      quarantines
      |> Enum.filter(&quarantine_matches?(&1, evidence_item, requirement))
      |> Enum.map(& &1["id"])
    end)
    |> Enum.uniq()
  end

  defp quarantine_matches?(%{"status" => "quarantined"} = quarantine, evidence, requirement) do
    obligation_id = requirement["verification_obligation_id"]

    obligation_id in quarantine["required_for_obligation_ids"] and
      (quarantine["evidence_ref"] == evidence["id"] or
         quarantine["test_pack_id"] == evidence["producer_ref"] or
         quarantine["test_id"] == evidence["producer_ref"])
  end

  defp quarantine_matches?(_quarantine, _evidence, _requirement), do: false

  defp satisfaction_result(dimension_results, waived?) do
    statuses = dimension_results |> Map.values() |> Enum.map(& &1["status"])

    cond do
      Enum.all?(statuses, &(&1 == "satisfied")) -> "satisfied"
      waived? -> "waived"
      Enum.any?(statuses, &(&1 == "blocked")) -> "blocked"
      true -> "not_assessed"
    end
  end

  defp apply_waiver(dimension_results, "waived") do
    Map.new(dimension_results, fn
      {dimension, %{"status" => "satisfied"} = result} -> {dimension, result}
      {dimension, result} -> {dimension, %{result | "status" => "waived"}}
    end)
  end

  defp apply_waiver(dimension_results, _result), do: dimension_results

  defp consumed_evidence_ids(_requirement, _dimension_results, "waived"), do: []
  defp consumed_evidence_ids(_requirement, _dimension_results, "not_assessed"), do: []

  defp consumed_evidence_ids(requirement, dimension_results, _result) do
    requirement["required_dimensions"]
    |> Enum.flat_map(&get_in(dimension_results, [&1, "evidence_ids"]))
    |> Enum.uniq()
  end

  defp maybe_put_waiver(satisfaction, %{"id" => waiver_id}, "waived"),
    do: Map.put(satisfaction, "waiver_id", waiver_id)

  defp maybe_put_waiver(satisfaction, _waiver, _result), do: satisfaction

  defp active_waiver?(%{"status" => "active"} = waiver, requirement),
    do: waiver["verification_obligation_id"] == requirement["verification_obligation_id"]

  defp active_waiver?(_waiver, _requirement), do: false

  defp required_enum(attrs, key, allowed) do
    value = value(attrs, key)
    normalized = normalize_enum(value)

    if normalized in allowed do
      normalized
    else
      raise ArgumentError, "#{key} must be one of #{Enum.join(allowed, ", ")}"
    end
  end

  defp required_enum_list(attrs, key, allowed) do
    case value(attrs, key) do
      values when is_list(values) and values != [] ->
        Enum.map(values, fn item ->
          normalized = normalize_enum(item)

          if normalized in allowed do
            normalized
          else
            raise ArgumentError, "#{key} must contain only #{Enum.join(allowed, ", ")}"
          end
        end)

      _other ->
        raise ArgumentError, "#{key} must be a non-empty list"
    end
  end

  defp normalize_enum(nil), do: nil
  defp normalize_enum(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_enum(value) when is_binary(value), do: value
  defp normalize_enum(_value), do: nil

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

  defp required_boolean(attrs, key) do
    case value(attrs, key) do
      value when is_boolean(value) -> value
      _other -> raise ArgumentError, "#{key} must be a boolean"
    end
  end

  defp required_string_list(attrs, key) do
    case value(attrs, key) do
      values when is_list(values) and values != [] ->
        Enum.map(values, fn
          value when is_atom(value) and not is_nil(value) -> Atom.to_string(value)
          value when is_binary(value) and value != "" -> value
          _other -> raise ArgumentError, "#{key} must contain only non-empty strings"
        end)

      _other ->
        raise ArgumentError, "#{key} must be a non-empty list"
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

  defp value(map, key) do
    cond do
      Map.has_key?(map, key) -> Map.get(map, key)
      Map.has_key?(map, to_string(key)) -> Map.get(map, to_string(key))
      true -> nil
    end
  end
end
