defmodule Conveyor.BehaviorOracleAdapter do
  @moduledoc """
  Bounded behavior oracle for pure-refactor fixtures.

  The adapter compares base and candidate behavior only over the fixture's
  declared input set. A passing result is intentionally phrased as an
  observation, not as a proof of general equivalence.
  """

  @schema_version "conveyor.behavior_oracle_result@1"
  @bounded_claim "bounded_observation_only"
  @normalized_value "__conveyor_normalized_nondeterminism__"

  @spec evaluate!(map()) :: map()
  def evaluate!(%{} = fixture) do
    fixture_id = fetch!(fixture, :fixture_id)
    inputs = fetch!(fixture, :inputs)
    base_runner = fetch!(fixture, :base_runner)
    candidate_runner = fetch!(fixture, :candidate_runner)
    normalize_paths = Map.get(fixture, :normalize_paths, Map.get(fixture, "normalize_paths", []))

    if inputs == [] do
      missing_inputs_result(fixture_id, normalize_paths)
    else
      evaluate_inputs(fixture_id, inputs, base_runner, candidate_runner, normalize_paths)
    end
  end

  defp missing_inputs_result(fixture_id, normalize_paths) do
    %{
      "schema_version" => @schema_version,
      "fixture_id" => fixture_id,
      "result" => "inconclusive",
      "equivalence_claim" => @bounded_claim,
      "input_count" => 0,
      "normalized_paths" => normalize_paths,
      "findings" => [
        %{
          "category" => "missing_bounded_inputs",
          "message" => "behavior oracle requires at least one bounded input"
        }
      ]
    }
  end

  defp evaluate_inputs(fixture_id, inputs, base_runner, candidate_runner, normalize_paths) do
    observations =
      inputs
      |> Enum.with_index()
      |> Enum.map(fn {input, index} ->
        observe(input, index, base_runner, candidate_runner, normalize_paths)
      end)

    inconclusive_findings =
      observations
      |> Enum.filter(&Map.has_key?(&1, :inconclusive_finding))
      |> Enum.map(& &1.inconclusive_finding)

    divergence_findings =
      observations
      |> Enum.reject(& &1.match?)
      |> Enum.reject(&Map.has_key?(&1, :inconclusive_finding))
      |> Enum.map(&finding/1)

    findings = inconclusive_findings ++ divergence_findings
    result_status = result_status(inconclusive_findings, divergence_findings)

    result =
      %{
        "schema_version" => @schema_version,
        "fixture_id" => fixture_id,
        "result" => result_status,
        "equivalence_claim" => @bounded_claim,
        "input_count" => length(inputs),
        "normalized_paths" => normalize_paths,
        "findings" => findings
      }

    result
    |> maybe_put_first_inconclusive(inconclusive_findings)
    |> maybe_put_first_divergence(divergence_findings)
  end

  defp observe(input, index, base_runner, candidate_runner, normalize_paths) do
    with {:ok, base} <- run_runner("base", base_runner, input, index, normalize_paths),
         {:ok, candidate} <-
           run_runner("candidate", candidate_runner, input, index, normalize_paths) do
      %{
        index: index,
        input: input,
        base: base,
        candidate: candidate,
        match?: base == candidate
      }
    else
      {:error, finding} ->
        %{index: index, input: input, match?: true, inconclusive_finding: finding}
    end
  end

  defp run_runner(runner_name, runner, input, index, normalize_paths) do
    {:ok, input |> runner.() |> normalize(normalize_paths)}
  rescue
    error ->
      {:error,
       %{
         "category" => "oracle_execution_error",
         "runner" => runner_name,
         "input_index" => index,
         "message" => Exception.message(error)
       }}
  end

  defp result_status([_first | _rest], _divergence_findings), do: "inconclusive"
  defp result_status([], [_first | _rest]), do: "diverged"
  defp result_status([], []), do: "no_divergence_observed"

  defp finding(observation) do
    %{
      "category" => "behavior_divergence",
      "input_index" => observation.index,
      "input" => observation.input,
      "base_observation" => observation.base,
      "candidate_observation" => observation.candidate
    }
  end

  defp maybe_put_first_divergence(result, []), do: result

  defp maybe_put_first_divergence(result, [first_finding | _findings]) do
    Map.put(result, "first_divergence_index", first_finding["input_index"])
  end

  defp maybe_put_first_inconclusive(result, []), do: result

  defp maybe_put_first_inconclusive(result, [first_finding | _findings]) do
    Map.put(result, "first_inconclusive_index", first_finding["input_index"])
  end

  defp normalize(value, paths) do
    Enum.reduce(paths, value, &put_normalized_path(&2, &1))
  end

  defp put_normalized_path(value, []), do: value

  defp put_normalized_path(%{} = map, [key]) do
    case existing_key(map, key) do
      {:ok, map_key} -> Map.put(map, map_key, @normalized_value)
      :error -> map
    end
  end

  defp put_normalized_path(%{} = map, [key | rest]) do
    case existing_key(map, key) do
      {:ok, map_key} -> Map.update!(map, map_key, &put_normalized_path(&1, rest))
      :error -> map
    end
  end

  defp put_normalized_path(value, _path), do: value

  defp existing_key(map, key) do
    Enum.find_value(key_candidates(key), :error, fn candidate ->
      if Map.has_key?(map, candidate), do: {:ok, candidate}
    end)
  end

  defp key_candidates(key) when is_binary(key) do
    case existing_atom(key) do
      nil -> [key]
      atom -> [key, atom]
    end
  end

  defp key_candidates(key) when is_atom(key), do: [key, Atom.to_string(key)]
  defp key_candidates(key), do: [key]

  defp existing_atom(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> nil
  end

  defp fetch!(map, key) do
    Map.fetch!(map, key)
  rescue
    KeyError -> Map.fetch!(map, Atom.to_string(key))
  end
end
