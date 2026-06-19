defmodule Conveyor.Recovery do
  @moduledoc """
  Typed recovery proposal and action builders.

  Recovery is keyed by registry action names. CLI/UI affordances can project
  these keys, but raw shell commands are not authoritative recovery data.
  """

  @actions %{
    "retry_with_fresh_permit" => %{
      requires_new_spec: false,
      requires_new_attempt: true,
      idempotent: true,
      precondition_policy_key: "recovery.retry.fenced"
    },
    "rebuild_stale_projection" => %{
      requires_new_spec: false,
      requires_new_attempt: false,
      idempotent: true,
      precondition_policy_key: "recovery.rebuild_projection.fenced"
    },
    "rerun_stale_canary" => %{
      requires_new_spec: false,
      requires_new_attempt: false,
      idempotent: true,
      precondition_policy_key: "recovery.rerun_canary.fenced"
    },
    "pause_under_emergency" => %{
      requires_new_spec: false,
      requires_new_attempt: false,
      idempotent: true,
      precondition_policy_key: "recovery.pause.emergency"
    }
  }

  @spec action_registry() :: map()
  def action_registry, do: @actions

  @spec new_proposal!(map()) :: map()
  def new_proposal!(attrs) when is_map(attrs) do
    action_key = attrs |> value(:action_key) |> to_string()

    action =
      Map.get(@actions, action_key) ||
        raise ArgumentError, "unknown recovery action_key: #{action_key}"

    proposal = %{
      "schema_version" => "conveyor.recovery_proposal@1",
      "failure_diagnosis_id" => required(attrs, :failure_diagnosis_id),
      "action_key" => action_key,
      "arguments_ref" => required(attrs, :arguments_ref),
      "reusable_artifact_refs" => list_value(attrs, :reusable_artifact_refs),
      "invalidated_artifact_refs" => list_value(attrs, :invalidated_artifact_refs),
      "requires_new_spec" => boolean_value(attrs, :requires_new_spec, action.requires_new_spec),
      "requires_new_attempt" =>
        boolean_value(attrs, :requires_new_attempt, action.requires_new_attempt),
      "requires_human" => boolean_value(attrs, :requires_human, false),
      "idempotent" => boolean_value(attrs, :idempotent, action.idempotent),
      "precondition_policy_key" =>
        value(attrs, :precondition_policy_key, action.precondition_policy_key)
    }

    Map.put(proposal, "proposal_digest", digest(proposal))
  end

  @spec authorize_action!(map(), keyword()) :: map()
  def authorize_action!(proposal, opts) when is_map(proposal) and is_list(opts) do
    action_key = required(proposal, :action_key)

    unless Map.has_key?(@actions, action_key) do
      raise ArgumentError, "unknown recovery action_key: #{action_key}"
    end

    arguments_digest = digest(required(proposal, :arguments_ref))

    %{
      "schema_version" => "conveyor.recovery_action@1",
      "recovery_proposal_id" => required(proposal, :proposal_digest),
      "action_key" => action_key,
      "authorized_by" => Keyword.fetch!(opts, :authorized_by),
      "authorization_ref" => Keyword.fetch!(opts, :authorization_ref),
      "arguments_digest" => arguments_digest,
      "status" => "pending",
      "idempotency_key" =>
        "recovery:#{action_key}:#{String.replace_prefix(arguments_digest, "sha256:", "")}",
      "created_at" => Keyword.fetch!(opts, :created_at)
    }
  end

  @safe_auto_criteria [
    "deterministic_precondition",
    "current_fence",
    "active_grant",
    "budget_reserved",
    "idempotent",
    "bounded_retry"
  ]

  @spec safe_auto_action_decision(map(), map()) :: map()
  def safe_auto_action_decision(proposal, evidence)
      when is_map(proposal) and is_map(evidence) do
    action_key = required(proposal, :action_key)

    unless Map.has_key?(@actions, action_key) do
      raise ArgumentError, "unknown recovery action_key: #{action_key}"
    end

    satisfied =
      @safe_auto_criteria
      |> Enum.filter(&criterion_satisfied?(&1, proposal, evidence))

    failed = @safe_auto_criteria -- satisfied
    human_gates = human_gated_reasons(proposal)
    auto_apply? = failed == [] and human_gates == []

    %{
      "schema_version" => "conveyor.safe_auto_action_decision@1",
      "proposal_digest" => required(proposal, :proposal_digest),
      "action_key" => action_key,
      "decision" => if(auto_apply?, do: "auto_applicable", else: "human_required"),
      "auto_apply" => auto_apply?,
      "requires_human" => not auto_apply?,
      "satisfied_criteria" => satisfied,
      "failed_criteria" => failed,
      "human_gated_reasons" => human_gates
    }
  end

  defp required(map, key) do
    value(map, key) || raise ArgumentError, "#{key} is required"
  end

  defp value(map, key, default \\ nil) do
    string_key = to_string(key)
    atom_key = existing_atom_key(key)

    cond do
      Map.has_key?(map, key) -> Map.fetch!(map, key)
      Map.has_key?(map, string_key) -> Map.fetch!(map, string_key)
      not is_nil(atom_key) and Map.has_key?(map, atom_key) -> Map.fetch!(map, atom_key)
      true -> default
    end
  end

  defp existing_atom_key(key) when is_atom(key), do: key

  defp existing_atom_key(key) do
    String.to_existing_atom(to_string(key))
  rescue
    ArgumentError -> nil
  end

  defp list_value(map, key) do
    case value(map, key, []) do
      values when is_list(values) -> values
      other -> raise ArgumentError, "#{key} must be a list, got: #{inspect(other)}"
    end
  end

  defp boolean_value(map, key, default) do
    case value(map, key, default) do
      value when is_boolean(value) -> value
      other -> raise ArgumentError, "#{key} must be a boolean, got: #{inspect(other)}"
    end
  end

  defp criterion_satisfied?("idempotent", proposal, _evidence),
    do: value(proposal, :idempotent) == true

  defp criterion_satisfied?(criterion, _proposal, evidence),
    do: value(evidence, criterion) == true

  defp human_gated_reasons(proposal) do
    [
      {value(proposal, :requires_human) == true, "requires_human"},
      {value(proposal, :requires_new_spec) == true, "requires_new_spec"}
    ]
    |> Enum.filter(&elem(&1, 0))
    |> Enum.map(&elem(&1, 1))
  end

  defp digest(value), do: Conveyor.CanonicalJson.digest(value)
end
