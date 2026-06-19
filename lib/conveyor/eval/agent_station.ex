defmodule Conveyor.Eval.AgentStation do
  @moduledoc """
  Agent-invoking station (idea #2). Runs an `AgentRunner` adapter (the deterministic
  `ReferenceSolution` by default) through the normalized `AgentRunner.run/5`
  boundary and records the produced workspace diff as an artifact.

  ADR-07: the agent's output (its patch + prose) is treated as untrusted **data**,
  never instruction authority. ADR-08: the `Conveyor.Station` wrapper supplies the
  lease epoch + fencing token + EffectReceipts — this station just declares
  `effects/0`. The provisional contract path (station_plan standing in for
  ContractLock+AgentBrief) is the B2 divergence; see `WorkGraphToStationPlan`.
  """

  use Conveyor.Station, station: "agent"

  alias Conveyor.AgentRunner
  alias Conveyor.AgentRunner.ReferenceSolution
  alias Conveyor.Factory
  alias Conveyor.Factory.{AgentSession, Policy, RunPrompt}

  @impl Conveyor.Station
  def effects(_input), do: [:file_write]

  @impl Conveyor.Station
  def run(input, context) do
    adapter = adapter_module(input)
    agent_session = agent_session!(context.run_attempt.id)
    run_prompt = Ash.get!(RunPrompt, agent_session.run_prompt_id, domain: Factory)
    workspace = %{path: get(input, "workspace_path"), base_commit: get(input, "base_commit")}

    opts = [
      agent_session_id: agent_session.id,
      run_attempt_id: context.run_attempt.id,
      blob_root: get(input, "blob_root"),
      reference_patch: get(input, "patch_ref"),
      session_id: "golden-#{context.run_attempt.id}"
    ]

    case AgentRunner.run(adapter, run_prompt, workspace, policy(), opts) do
      {:ok, raw} ->
        artifact = %{
          kind: "agent_diff",
          media_type: "text/x-diff",
          projection_path: "agent/diff.patch",
          content_ref: raw.diff_ref
        }

        {:ok,
         %{
           "adapter" => to_string(adapter),
           "diff_ref" => raw.diff_ref,
           "patch_set_id" => raw.metadata["patch_set_id"],
           artifacts: [artifact]
         }}

      {:error, reason} ->
        {:error, {:agent_failed, reason}}
    end
  end

  defp adapter_module(input) do
    case get(input, "adapter") do
      nil -> ReferenceSolution
      module when is_atom(module) -> module
      name when is_binary(name) -> Module.concat([name])
    end
  end

  defp agent_session!(run_attempt_id) do
    AgentSession
    |> Ash.read!(domain: Factory)
    |> Enum.find(&(&1.run_attempt_id == run_attempt_id))
  end

  defp policy do
    %Policy{
      name: "implement",
      profile: :implement,
      allowlist: ["reference"],
      denylist: [],
      env_policy: %{"allowlist" => []},
      network_policy: %{"default" => "none"},
      budget_policy: %{},
      autonomy_ceiling: 2
    }
  end

  defp get(input, key), do: Map.get(input, key) || Map.get(input, String.to_atom(key))
end
