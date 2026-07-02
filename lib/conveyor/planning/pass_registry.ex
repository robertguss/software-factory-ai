defmodule Conveyor.Planning.PassRegistry do
  @moduledoc """
  Generic deterministic pure-pass registry with restricted read context.
  """

  defstruct passes: %{}, cache: %{}

  defmodule Context do
    @moduledoc "Restricted pass context."
    defstruct [:inputs, :selectors]
    @type t :: %__MODULE__{}
  end

  defmodule Result do
    @moduledoc "Pure pass run result."
    defstruct [
      :status,
      :hermeticity_status,
      :output,
      :cache_key,
      :cache_status,
      :registry,
      :authority_effect
    ]

    @type t :: %__MODULE__{}
  end

  @spec new() :: %__MODULE__{}
  def new, do: %__MODULE__{}

  @spec register(%__MODULE__{}, map()) :: %__MODULE__{}
  def register(%__MODULE__{} = registry, pass) do
    normalized = normalize_pass(pass)
    %{registry | passes: Map.put(registry.passes, normalized.pass_key, normalized)}
  end

  @spec run(%__MODULE__{}, String.t(), map()) :: Result.t()
  def run(%__MODULE__{} = registry, pass_key, inputs) do
    pass = Map.fetch!(registry.passes, pass_key)
    cache_key = cache_key(pass, inputs)

    case Map.fetch(registry.cache, cache_key) do
      {:ok, output} ->
        %Result{
          status: :ok,
          hermeticity_status: :hermetic,
          output: output,
          cache_key: cache_key,
          cache_status: :hit,
          registry: registry,
          authority_effect: pass.authority_effect
        }

      :error ->
        context = %Context{inputs: inputs, selectors: MapSet.new(pass.selectors)}
        output = pass.run.(context)
        registry = %{registry | cache: Map.put(registry.cache, cache_key, output)}

        %Result{
          status: :ok,
          hermeticity_status: :hermetic,
          output: output,
          cache_key: cache_key,
          cache_status: :miss,
          registry: registry,
          authority_effect: pass.authority_effect
        }
    end
  end

  @spec read!(Context.t(), String.t()) :: term()
  def read!(%Context{} = context, selector) do
    if MapSet.member?(context.selectors, selector) do
      Map.fetch!(context.inputs, selector)
    else
      raise ArgumentError, "undeclared pass read: #{selector}"
    end
  end

  defp normalize_pass(pass) do
    %{
      pass_key: value(pass, :pass_key),
      version: value(pass, :version),
      input_stage: value(pass, :input_stage),
      output_stage: value(pass, :output_stage),
      selectors: value(pass, :selectors) || [],
      cache_policy: value(pass, :cache_policy),
      authority_effect: value(pass, :authority_effect),
      run: value(pass, :run)
    }
  end

  defp cache_key(pass, inputs) do
    semantic_digest = value(inputs, :semantic_digest)
    authority_digest = value(inputs, :authority_digest)

    digest(
      canonical_json(%{
        pass_key: pass.pass_key,
        version: pass.version,
        semantic_digest: semantic_digest,
        authority_digest: authority_digest,
        selectors: pass.selectors
      })
    )
  end

  defp value(map, key), do: Map.get(map, key) || Map.get(map, to_string(key))

  defp digest(content) when is_binary(content) do
    "sha256:" <> Base.encode16(:crypto.hash(:sha256, content), case: :lower)
  end

  defp canonical_json(value) when is_map(value) do
    entries =
      value
      |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
      |> Enum.map(fn {key, nested} ->
        Jason.encode!(to_string(key)) <> ":" <> canonical_json(nested)
      end)

    "{" <> Enum.join(entries, ",") <> "}"
  end

  defp canonical_json(value) when is_list(value),
    do: "[" <> Enum.map_join(value, ",", &canonical_json/1) <> "]"

  defp canonical_json(value) when is_atom(value), do: value |> Atom.to_string() |> Jason.encode!()
  defp canonical_json(value), do: Jason.encode!(value)
end
