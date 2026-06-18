defmodule Conveyor.AgentRunner.SessionLimits do
  @moduledoc """
  Tracks live agent session wall-clock, idle, and output-size limits.
  """

  @type finding :: %{
          required(String.t()) => String.t() | non_neg_integer() | map()
        }

  @type t :: %__MODULE__{
          max_wall_clock_ms: non_neg_integer() | nil,
          max_idle_ms: non_neg_integer() | nil,
          max_output_bytes: non_neg_integer() | nil,
          started_at_ms: integer(),
          last_activity_at_ms: integer(),
          output_bytes: non_neg_integer()
        }

  defstruct max_wall_clock_ms: nil,
            max_idle_ms: nil,
            max_output_bytes: nil,
            started_at_ms: nil,
            last_activity_at_ms: nil,
            output_bytes: 0

  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    now_ms = Keyword.get(opts, :now_ms, System.monotonic_time(:millisecond))

    %__MODULE__{
      max_wall_clock_ms: optional_non_negative_integer!(opts, :max_wall_clock_ms),
      max_idle_ms: optional_non_negative_integer!(opts, :max_idle_ms),
      max_output_bytes: optional_non_negative_integer!(opts, :max_output_bytes),
      started_at_ms: now_ms,
      last_activity_at_ms: now_ms,
      output_bytes: 0
    }
  end

  @spec observe(t(), map()) :: {:ok, t()} | {:halt, finding(), map()}
  def observe(%__MODULE__{} = limits, event) when is_map(event) do
    event = normalize_keys(event)
    now_ms = Map.get(event, :observed_at_ms, System.monotonic_time(:millisecond))
    output_bytes = limits.output_bytes + output_size(event)
    wall_clock_ms = max(now_ms - limits.started_at_ms, 0)
    idle_ms = max(now_ms - limits.last_activity_at_ms, 0)

    measurements = %{
      wall_clock_ms: wall_clock_ms,
      idle_ms: idle_ms,
      output_bytes: output_bytes
    }

    cond do
      exceeded?(limits.max_wall_clock_ms, wall_clock_ms) ->
        {:halt, finding(:max_wall_clock_ms, limits.max_wall_clock_ms, measurements), measurements}

      exceeded?(limits.max_idle_ms, idle_ms) ->
        {:halt, finding(:max_idle_ms, limits.max_idle_ms, measurements), measurements}

      exceeded?(limits.max_output_bytes, output_bytes) ->
        {:halt, finding(:max_output_bytes, limits.max_output_bytes, measurements), measurements}

      true ->
        {:ok, %{limits | last_activity_at_ms: now_ms, output_bytes: output_bytes}}
    end
  end

  @spec finding(atom(), non_neg_integer(), map()) :: finding()
  def finding(cap, limit, measurements) do
    %{
      "severity" => "blocking",
      "category" => "agent_session_limit",
      "message" => "#{cap} exceeded during agent session",
      "exceeded_cap" => Atom.to_string(cap),
      "limit" => limit,
      "measurements" => stringify_keys(measurements)
    }
  end

  defp optional_non_negative_integer!(opts, key) do
    case Keyword.get(opts, key) do
      nil -> nil
      value when is_integer(value) and value >= 0 -> value
      _value -> raise ArgumentError, "#{key} must be a non-negative integer"
    end
  end

  defp output_size(event), do: byte_size(Jason.encode!(event))
  defp exceeded?(nil, _value), do: false
  defp exceeded?(limit, value), do: value > limit

  defp normalize_keys(map) do
    Map.new(map, fn
      {key, value} when is_binary(key) -> {String.to_existing_atom(key), value}
      pair -> pair
    end)
  end

  defp stringify_keys(map) do
    Map.new(map, fn {key, value} -> {Atom.to_string(key), value} end)
  end
end
