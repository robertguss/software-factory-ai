defmodule Conveyor.Cassettes.Nondeterminism do
  @moduledoc """
  Deterministic virtual clock, id allocator, and nondeterminism ledger.
  """

  defstruct seed: nil,
            clock_start: nil,
            clock_reads: [],
            id_counters: %{},
            id_allocations: [],
            env_reads: [],
            external_reads: [],
            tool_equivalence_policies: []

  @type t :: %__MODULE__{}

  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      seed: Keyword.fetch!(opts, :seed),
      clock_start: Keyword.get(opts, :clock_start, "1970-01-01T00:00:00Z")
    }
  end

  @spec tick(t(), atom()) :: {String.t(), t()}
  def tick(%__MODULE__{} = state, label) when is_atom(label) do
    index = length(state.clock_reads)
    timestamp = advance_iso8601(state.clock_start, index)
    read = %{label: label, timestamp: timestamp, ordinal: index + 1}

    {timestamp, %{state | clock_reads: state.clock_reads ++ [read]}}
  end

  @spec allocate_id(t(), String.t()) :: {String.t(), t()}
  def allocate_id(%__MODULE__{} = state, namespace) when is_binary(namespace) do
    next = Map.get(state.id_counters, namespace, 0) + 1
    id = "#{namespace}-#{String.pad_leading(Integer.to_string(next), 6, "0")}"
    allocation = %{namespace: namespace, id: id, ordinal: next}

    {id,
     %{
       state
       | id_counters: Map.put(state.id_counters, namespace, next),
         id_allocations: state.id_allocations ++ [allocation]
     }}
  end

  def record_env_read(%__MODULE__{} = state, key, value) do
    %{state | env_reads: state.env_reads ++ [%{key: key, value: value}]}
  end

  def record_external_read(%__MODULE__{} = state, subject, version_ref) do
    %{
      state
      | external_reads: state.external_reads ++ [%{subject: subject, version_ref: version_ref}]
    }
  end

  def record_tool_equivalence_policy(%__MODULE__{} = state, tool_contract_key, policy_version) do
    %{
      state
      | tool_equivalence_policies:
          state.tool_equivalence_policies ++
            [%{tool_contract_key: tool_contract_key, policy_version: policy_version}]
    }
  end

  @spec ledger(t()) :: map()
  def ledger(%__MODULE__{} = state) do
    %{
      "schema_version" => "conveyor.nondeterminism_ledger@1",
      "rng_seed" => state.seed,
      "clock_reads" => stringify(state.clock_reads),
      "id_allocations" => stringify(state.id_allocations),
      "env_reads" => stringify(state.env_reads),
      "external_reads" => stringify(state.external_reads),
      "tool_equivalence_policies" => stringify(state.tool_equivalence_policies)
    }
  end

  def require_complete(ledger, opts) when is_map(ledger) do
    missing =
      opts
      |> Keyword.get(:required, [])
      |> Enum.reject(&complete?(ledger, &1))

    if missing == [] do
      :ok
    else
      {:error, %{reason: :replay_incomplete, missing: missing}}
    end
  end

  defp complete?(ledger, :rng_seed), do: present?(Map.get(ledger, "rng_seed"))

  defp complete?(ledger, key) do
    case Map.get(ledger, Atom.to_string(key)) do
      values when is_list(values) -> values != []
      value -> present?(value)
    end
  end

  defp advance_iso8601(start, seconds) do
    start
    |> DateTime.from_iso8601()
    |> case do
      {:ok, datetime, _offset} ->
        DateTime.add(datetime, seconds, :second) |> DateTime.to_iso8601()

      _other ->
        start
    end
  end

  defp stringify(values) when is_list(values), do: Enum.map(values, &stringify/1)

  defp stringify(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), stringify(value)} end)
  end

  defp stringify(value), do: value
  defp present?(value), do: not is_nil(value) and value != ""
end
