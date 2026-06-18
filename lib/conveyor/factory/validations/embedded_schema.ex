defmodule Conveyor.Factory.Validations.EmbeddedSchema do
  @moduledoc false

  use Ash.Resource.Validation

  alias Ash.Error.Changes.InvalidAttribute

  @impl true
  def validate(changeset, opts, _context) do
    field = Keyword.fetch!(opts, :field)
    schema = Keyword.fetch!(opts, :schema)
    value = Ash.Changeset.get_attribute(changeset, field)

    case validate_value(schema, value) do
      :ok -> :ok
      {:error, message} -> {:error, InvalidAttribute.exception(field: field, message: message)}
    end
  end

  defp validate_value(schema, values)
       when schema in [:acceptance_criteria, :command_specs, :findings, :risk_rules] do
    validate_list(schema, values)
  end

  defp validate_value(:command_spec, value), do: validate_map(:command_spec, value)

  defp validate_list(_schema, values) when not is_list(values), do: {:error, "must be a list"}

  defp validate_list(schema, values) do
    values
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {value, index}, :ok ->
      case validate_map(schema, value) do
        :ok -> {:cont, :ok}
        {:error, message} -> {:halt, {:error, "entry #{index} #{message}"}}
      end
    end)
  end

  defp validate_map(schema, value) when not is_map(value), do: {:error, "#{schema} must be a map"}

  defp validate_map(:acceptance_criteria, value) do
    with :ok <- require_string(value, :id),
         :ok <- require_string(value, :text),
         :ok <-
           require_enum(value, :kind, [:behavioral, :test, :quality, :security, :documentation]),
         :ok <- require_string_list(value, :requirement_refs),
         :ok <- require_string_list(value, :required_test_refs),
         :ok <- require_enum(value, :evidence_status, [:missing, :passed, :failed, :skipped]),
         :ok <- require_string_list(value, :evidence_refs) do
      :ok
    end
  end

  defp validate_map(schema, value) when schema in [:command_spec, :command_specs] do
    with :ok <- require_string(value, :key),
         :ok <- require_string_list(value, :argv),
         :ok <- require_string(value, :cwd),
         :ok <-
           require_enum(value, :profile, [:explore, :implement, :verify, :release, :maintenance]),
         :ok <- require_boolean(value, :required),
         :ok <- require_integer(value, :timeout_ms),
         :ok <- require_enum(value, :network, [:none, :limited, :full]),
         :ok <- require_string_list(value, :env_allowlist),
         :ok <- require_integer(value, :output_limit_bytes),
         :ok <- require_integer(value, :repeat),
         :ok <-
           require_enum(value, :flake_policy, [:fail_closed, :quarantine, :allow_with_warning]),
         :ok <- require_map(value, :infra_retry_policy),
         :ok <- require_enum(value, :result_format, [:junit, :tap, :json, :stdout]) do
      :ok
    end
  end

  defp validate_map(:findings, value) do
    with :ok <- require_enum(value, :severity, [:blocking, :warning, :note]),
         :ok <-
           require_enum(value, :category, [
             :brief,
             :context,
             :execution,
             :validation,
             :review,
             :policy
           ]),
         :ok <- require_string(value, :message),
         :ok <- require_string_list(value, :artifact_refs),
         :ok <- require_list(value, :next_actions) do
      validate_next_actions(get(value, :next_actions))
    end
  end

  defp validate_map(:risk_rules, value) do
    with :ok <- require_map(value, :when),
         :ok <- require_enum(value, :observed_risk, [:low, :medium, :high, :critical]),
         :ok <-
           require_enum_list(value, :required_review_kinds, [
             :general,
             :security,
             :test,
             :architecture
           ]),
         :ok <- require_boolean(value, :require_human_approval) do
      :ok
    end
  end

  defp validate_next_actions(actions) do
    actions
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {action, index}, :ok ->
      case validate_next_action(action) do
        :ok -> {:cont, :ok}
        {:error, message} -> {:halt, {:error, "next_actions entry #{index} #{message}"}}
      end
    end)
  end

  defp validate_next_action(action) when not is_map(action), do: {:error, "must be a map"}

  defp validate_next_action(action) do
    with :ok <-
           require_enum(action, :kind, [
             :edit_plan,
             :edit_brief,
             :fix_policy,
             :rerun_station,
             :inspect_artifact,
             :record_human_decision
           ]),
         :ok <- require_string(action, :label),
         :ok <- optional_string(action, :command) do
      :ok
    end
  end

  defp require_string(map, key) do
    case get(map, key) do
      value when is_binary(value) and value != "" -> :ok
      _ -> {:error, "#{key} must be a non-empty string"}
    end
  end

  defp optional_string(map, key) do
    case get(map, key) do
      nil -> :ok
      value when is_binary(value) and value != "" -> :ok
      _ -> {:error, "#{key} must be a non-empty string when present"}
    end
  end

  defp require_integer(map, key) do
    case get(map, key) do
      value when is_integer(value) -> :ok
      _ -> {:error, "#{key} must be an integer"}
    end
  end

  defp require_boolean(map, key) do
    case get(map, key) do
      value when is_boolean(value) -> :ok
      _ -> {:error, "#{key} must be a boolean"}
    end
  end

  defp require_map(map, key) do
    case get(map, key) do
      value when is_map(value) -> :ok
      _ -> {:error, "#{key} must be a map"}
    end
  end

  defp require_list(map, key) do
    case get(map, key) do
      value when is_list(value) -> :ok
      _ -> {:error, "#{key} must be a list"}
    end
  end

  defp require_string_list(map, key) do
    case get(map, key) do
      values when is_list(values) ->
        if Enum.all?(values, &is_binary/1),
          do: :ok,
          else: {:error, "#{key} must be a list of strings"}

      _ ->
        {:error, "#{key} must be a list of strings"}
    end
  end

  defp require_enum_list(map, key, allowed) do
    case get(map, key) do
      values when is_list(values) ->
        if Enum.all?(values, &enum_value?(&1, allowed)),
          do: :ok,
          else: {:error, "#{key} contains an invalid enum value"}

      _ ->
        {:error, "#{key} must be a list"}
    end
  end

  defp require_enum(map, key, allowed) do
    if enum_value?(get(map, key), allowed),
      do: :ok,
      else: {:error, "#{key} has an invalid enum value"}
  end

  defp enum_value?(value, allowed) when is_atom(value), do: value in allowed

  defp enum_value?(value, allowed) when is_binary(value) do
    Enum.any?(allowed, &(Atom.to_string(&1) == value))
  end

  defp enum_value?(_value, _allowed), do: false

  defp get(map, key), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end
