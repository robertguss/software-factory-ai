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

  defp required(map, key) do
    value(map, key) || raise ArgumentError, "#{key} is required"
  end

  defp value(map, key, default \\ nil) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
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

  defp digest(value) do
    digest_input =
      value
      |> normalize_for_digest()
      |> :erlang.term_to_binary()

    "sha256:" <> Base.encode16(:crypto.hash(:sha256, digest_input), case: :lower)
  end

  defp normalize_for_digest(%{} = map) do
    map
    |> Enum.reject(fn {key, _value} -> to_string(key) in ["proposal_digest"] end)
    |> Enum.map(fn {key, value} -> {to_string(key), normalize_for_digest(value)} end)
    |> Enum.sort_by(&elem(&1, 0))
  end

  defp normalize_for_digest(values) when is_list(values),
    do: Enum.map(values, &normalize_for_digest/1)

  defp normalize_for_digest(value), do: value
end
