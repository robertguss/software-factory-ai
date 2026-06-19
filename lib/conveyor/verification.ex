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

  @waiver_statuses ~w(active expired revoked superseded)

  @spec obligation_kinds() :: [String.t()]
  def obligation_kinds, do: @obligation_kinds

  @spec evidence_kinds() :: [String.t()]
  def evidence_kinds, do: @evidence_kinds

  @spec validity_states() :: [String.t()]
  def validity_states, do: @validity_states

  @spec waiver_statuses() :: [String.t()]
  def waiver_statuses, do: @waiver_statuses

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

  defp required_enum(attrs, key, allowed) do
    value = value(attrs, key)
    normalized = normalize_enum(value)

    if normalized in allowed do
      normalized
    else
      raise ArgumentError, "#{key} must be one of #{Enum.join(allowed, ", ")}"
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

  defp value(map, key), do: Map.get(map, key) || Map.get(map, to_string(key))
end
