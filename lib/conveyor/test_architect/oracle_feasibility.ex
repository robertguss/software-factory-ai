defmodule Conveyor.TestArchitect.OracleFeasibility do
  @moduledoc """
  Deterministic oracle-feasibility classifier for Test Architect work.

  The classifier never weakens a vague or human-only oracle into an ordinary
  machine test. Boundary uncertainty routes back to decomposition/Contract Forge;
  human-only verification caps autonomy and requires human-observed evidence.
  """

  @spec classify!(map()) :: map()
  def classify!(input) when is_map(input) do
    normalized = stringify_map(input)

    base = %{
      "schema_version" => "conveyor.oracle_feasibility@1",
      "acceptance_ref" => required_string(normalized, "acceptance_ref"),
      "verification_obligation_ref" => required_string(normalized, "verification_obligation_ref")
    }

    base
    |> Map.merge(classification(normalized))
    |> put_digest()
  end

  defp classification(input) do
    cond do
      boundary_unclear?(input) ->
        %{
          "classification" => "boundary_unclear",
          "route" => "split_or_clarify",
          "autonomy_cap" => "blocked",
          "required_evidence_kinds" => [],
          "findings" => [
            %{
              "rule_key" => "oracle_feasibility.boundary_unclear",
              "severity" => "blocking",
              "message" => "Boundary-unclear oracle feasibility must route to split or clarify"
            }
          ]
        }

      machine_oracle?(input) and human_observation?(input) ->
        %{
          "classification" => "partially_automatable",
          "route" => "test_architect_with_human_observation",
          "autonomy_cap" => "supervised",
          "required_evidence_kinds" => ["candidate_result", "calibration", "human_observation"],
          "findings" => []
        }

      machine_oracle?(input) ->
        %{
          "classification" => "automatable",
          "route" => "test_architect",
          "autonomy_cap" => "normal",
          "required_evidence_kinds" => ["candidate_result", "calibration"],
          "findings" => []
        }

      human_observation?(input) ->
        %{
          "classification" => "not_automatable",
          "route" => "human_verification",
          "autonomy_cap" => "observe_only",
          "required_evidence_kinds" => ["human_observation"],
          "findings" => []
        }

      true ->
        %{
          "classification" => "boundary_unclear",
          "route" => "split_or_clarify",
          "autonomy_cap" => "blocked",
          "required_evidence_kinds" => [],
          "findings" => [
            %{
              "rule_key" => "oracle_feasibility.oracle_path_missing",
              "severity" => "blocking",
              "message" =>
                "Oracle feasibility needs a machine oracle or human observation procedure"
            }
          ]
        }
    end
  end

  defp boundary_unclear?(input), do: Map.get(input, "boundary_questions", []) != []

  defp machine_oracle?(input) do
    Map.get(input, "machine_oracle") == true and Map.get(input, "deterministic_inputs") == true and
      present?(Map.get(input, "result_adapter")) and Map.get(input, "oracle_assertions", []) != []
  end

  defp human_observation?(input), do: present?(Map.get(input, "human_observation_procedure"))

  defp put_digest(result) do
    digest =
      result
      |> canonical_term()
      |> Jason.encode!()
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)

    result
    |> Map.put("oracle_feasibility_digest", "sha256:#{digest}")
    |> Map.put("id", "oracle_feasibility:sha256:#{digest}")
  end

  defp required_string(map, key) do
    case Map.fetch!(map, key) do
      value when is_binary(value) and value != "" -> value
      _other -> raise ArgumentError, "#{key} must be a non-empty string"
    end
  end

  defp present?(value), do: is_binary(value) and value != ""

  defp canonical_term(value) when is_map(value) do
    value
    |> stringify_map()
    |> Enum.sort_by(fn {key, _value} -> key end)
    |> Enum.map(fn {key, value} -> [key, canonical_term(value)] end)
  end

  defp canonical_term(values) when is_list(values), do: Enum.map(values, &canonical_term/1)
  defp canonical_term(value), do: value

  defp stringify_map(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), stringify_value(value)} end)
  end

  defp stringify_value(value) when is_map(value), do: stringify_map(value)
  defp stringify_value(values) when is_list(values), do: Enum.map(values, &stringify_value/1)
  defp stringify_value(value) when is_boolean(value), do: value
  defp stringify_value(value) when is_atom(value), do: Atom.to_string(value)
  defp stringify_value(value), do: value
end
