defmodule Conveyor.AgentRunner.AgentProfile do
  @moduledoc """
  Snapshot of an agent adapter and its capability-derived autonomy ceiling.
  """

  alias Conveyor.AgentRunner.Capabilities

  @type t :: %__MODULE__{
          adapter: String.t(),
          model: String.t() | nil,
          capabilities: Capabilities.t(),
          autonomy_ceiling: String.t(),
          known_limitations: [atom()]
        }

  @enforce_keys [:adapter, :capabilities, :autonomy_ceiling, :known_limitations]
  defstruct [:adapter, :model, :capabilities, :autonomy_ceiling, :known_limitations]

  @spec new!(module(), keyword()) :: t()
  def new!(adapter_module, opts \\ []) do
    capabilities = adapter_module.capabilities() |> Capabilities.new!()

    %__MODULE__{
      adapter: Keyword.get(opts, :adapter, adapter_name(adapter_module)),
      model: Keyword.get(opts, :model),
      capabilities: capabilities,
      autonomy_ceiling: Capabilities.autonomy_ceiling(capabilities),
      known_limitations: capabilities.known_limitations
    }
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = profile) do
    %{
      "adapter" => profile.adapter,
      "model" => profile.model,
      "autonomy_ceiling" => profile.autonomy_ceiling,
      "capabilities" => Capabilities.to_map(profile.capabilities),
      "known_limitations" => Enum.map(profile.known_limitations, &Atom.to_string/1)
    }
  end

  defp adapter_name(adapter_module) do
    adapter_module
    |> Module.split()
    |> Enum.join(".")
  end
end
