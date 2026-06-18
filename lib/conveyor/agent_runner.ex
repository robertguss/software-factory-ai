defmodule Conveyor.AgentRunner do
  @moduledoc """
  Behaviour every coding-agent backend implements.
  """

  alias Conveyor.AgentRunner.AgentProfile
  alias Conveyor.AgentRunner.Capabilities
  alias Conveyor.AgentRunner.RawRunResult

  @callback capabilities() :: Capabilities.t() | map()
  @callback run(struct(), struct(), map(), keyword()) ::
              {:ok, RawRunResult.t()} | {:error, term()}
  @callback cancel(String.t()) :: :ok | {:error, term()}

  @spec agent_profile_snapshot(module(), keyword()) :: map()
  def agent_profile_snapshot(adapter_module, opts \\ []) do
    adapter_module
    |> AgentProfile.new!(opts)
    |> AgentProfile.to_map()
  end
end
