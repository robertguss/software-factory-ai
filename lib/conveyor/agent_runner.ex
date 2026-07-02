defmodule Conveyor.AgentRunner do
  @moduledoc """
  Behaviour every coding-agent backend implements.
  """

  alias Conveyor.AgentRunner.AgentProfile
  alias Conveyor.AgentRunner.Capabilities
  alias Conveyor.AgentRunner.RawRunResult

  @callback capabilities() :: Capabilities.t() | map()
  @callback run(struct(), map(), map(), keyword()) ::
              {:ok, RawRunResult.t()} | {:error, term()}
  @callback cancel(String.t()) :: :ok | {:error, term()}

  @spec run(module(), struct(), map(), map(), keyword()) ::
          {:ok, RawRunResult.t()} | {:error, term()}
  def run(adapter_module, run_prompt, workspace, policy, opts \\ [])
      when is_atom(adapter_module) and is_list(opts) do
    case adapter_module.run(run_prompt, workspace, policy, opts) do
      {:ok, %RawRunResult{} = result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
      other -> {:error, {:invalid_agent_runner_result, other}}
    end
  end

  @spec cancel(module(), String.t(), keyword()) :: :ok | {:error, term()}
  def cancel(adapter_module, session_id, opts \\ [])
      when is_atom(adapter_module) and is_binary(session_id) and is_list(opts) do
    if function_exported?(adapter_module, :cancel, 2) do
      adapter_module.cancel(session_id, opts)
    else
      adapter_module.cancel(session_id)
    end
  end

  @spec agent_profile_snapshot(module(), keyword()) :: map()
  def agent_profile_snapshot(adapter_module, opts \\ []) do
    adapter_module
    |> AgentProfile.new!(opts)
    |> AgentProfile.to_map()
  end
end
