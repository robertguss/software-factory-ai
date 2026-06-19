defmodule Conveyor.Cassettes.ReplayEngine do
  @moduledoc """
  Mode-specific cassette replay decisions.
  """

  @modes [:full, :hybrid, :proposal, :compatible]

  @spec replay(atom(), map(), keyword()) :: {:ok, map()} | {:error, map()}
  def replay(mode, cassette, opts \\ []) when mode in @modes and is_map(cassette) do
    with :ok <- require_fresh_generation(mode, cassette, opts),
         :ok <- strict_replay_check(mode, cassette, opts) do
      {:ok, replay_result(mode, cassette, opts)}
    end
  end

  defp require_fresh_generation(mode, cassette, opts) do
    current = Keyword.get(opts, :current_generation_freshness_digest)
    recorded = Map.get(cassette, "generation_freshness_digest")

    if current == recorded do
      :ok
    else
      {:error, %{mode: mode, status: :missed, reason: :cassette_generation_stale}}
    end
  end

  defp strict_replay_check(:full, cassette, opts) do
    recorded_tools = cassette |> Map.get("tool_records", []) |> Enum.map(&tool_signature/1)

    requested_tools =
      opts |> Keyword.get(:requested_tool_records, []) |> Enum.map(&tool_signature/1)

    recorded_events = cassette |> Map.get("causal_events", []) |> Enum.map(&event_signature/1)

    requested_events =
      opts |> Keyword.get(:requested_causal_events, []) |> Enum.map(&event_signature/1)

    if recorded_tools == requested_tools and recorded_events == requested_events do
      :ok
    else
      {:error, %{mode: :full, status: :missed, reason: :strict_replay_divergence}}
    end
  end

  defp strict_replay_check(_mode, _cassette, _opts), do: :ok

  defp replay_result(:full, cassette, _opts) do
    %{
      mode: :full,
      status: :replayed,
      trust_gate_eligible?: true,
      primary_outputs: Map.get(cassette, "primary_outputs", [])
    }
  end

  defp replay_result(:hybrid, cassette, opts) do
    current_eval = Keyword.get(opts, :current_evaluation_surface_digest)
    recorded_eval = Map.get(cassette, "evaluation_surface_digest")

    %{
      mode: :hybrid,
      status: :replayed,
      trust_gate_eligible?: true,
      evaluation_surface_changed?: present?(current_eval) and current_eval != recorded_eval,
      gate_results: Keyword.get(opts, :gate_results, [])
    }
  end

  defp replay_result(:proposal, _cassette, opts) do
    %{
      mode: :proposal,
      status: :replayed,
      trust_gate_eligible?: true,
      proposal_result: Keyword.get(opts, :proposal_result, %{})
    }
  end

  defp replay_result(:compatible, _cassette, _opts) do
    %{
      mode: :compatible,
      status: :compatible_only,
      trust_gate_eligible?: false
    }
  end

  defp tool_signature(record) do
    %{
      "tool_contract_key" => Map.get(record, "tool_contract_key"),
      "normalized_args" => canonical(Map.get(record, "normalized_args", %{}))
    }
  end

  defp event_signature(event) do
    %{
      "event_id" => Map.get(event, "event_id"),
      "happens_after" => Map.get(event, "happens_after", [])
    }
  end

  defp canonical(map) when is_map(map) do
    map
    |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
    |> Map.new(fn {key, value} -> {key, canonical(value)} end)
  end

  defp canonical(values) when is_list(values), do: Enum.map(values, &canonical/1)
  defp canonical(value), do: value

  defp present?(value), do: is_binary(value) and value != ""
end
