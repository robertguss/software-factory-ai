defmodule Conveyor.Stations.Implementer do
  @moduledoc "Production implementer station backed by an AgentRunner adapter."

  use Conveyor.Station, station: "implement"

  alias Conveyor.AgentRunner
  alias Conveyor.AgentRunner.Codex
  alias Conveyor.Factory
  alias Conveyor.Factory.{AgentSession, ContextPack, Policy, RunPrompt}
  alias Conveyor.PromptBuilder

  @impl Conveyor.Station
  def effects(_input), do: [:file_write]

  @impl Conveyor.Station
  def run(input, context) do
    adapter = adapter_module(input)
    agent_session = agent_session!(context.run_attempt, input)
    run_prompt = Ash.get!(RunPrompt, agent_session.run_prompt_id, domain: Factory)
    workspace = %{path: get(input, "workspace_path"), base_commit: get(input, "base_commit")}

    opts = [
      agent_session_id: agent_session.id,
      run_attempt_id: context.run_attempt.id,
      blob_root: get(input, "blob_root"),
      reference_patch: get(input, "patch_ref"),
      session_id: "run-#{context.run_attempt.id}"
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
           "adapter" => inspect(adapter),
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
      nil -> Codex
      module when is_atom(module) -> module
      name when is_binary(name) -> Module.concat([String.trim_leading(name, "Elixir.")])
    end
  end

  defp agent_session!(run_attempt, input) do
    AgentSession
    |> Ash.read!(domain: Factory)
    |> Enum.find(&(&1.run_attempt_id == run_attempt.id)) ||
      create_agent_session!(run_attempt, input)
  end

  defp create_agent_session!(run_attempt, input) do
    context_pack = context_pack!(get(input, "context_pack_id"))
    run_prompt = PromptBuilder.build!(run_attempt.slice_id, context_pack: context_pack)

    Ash.create!(
      AgentSession,
      %{
        run_attempt_id: run_attempt.id,
        run_prompt_id: run_prompt.id,
        agent_profile_id: Ash.UUID.generate(),
        role: :implementer,
        base_commit: run_attempt.base_commit,
        started_at: DateTime.utc_now(:microsecond),
        status: :running
      },
      domain: Factory
    )
  end

  defp context_pack!(nil),
    do:
      raise(
        ArgumentError,
        "implement station requires context_pack_id when no AgentSession exists"
      )

  defp context_pack!(id) do
    Ash.get!(ContextPack, id, domain: Factory)
  end

  defp policy do
    Policy
    |> Ash.read!(domain: Factory)
    |> Enum.find(&(&1.profile == :implement)) ||
      %Policy{
        name: "implement",
        profile: :implement,
        allowlist: [],
        denylist: [],
        env_policy: %{"allowlist" => []},
        network_policy: %{"default" => "none"},
        budget_policy: %{},
        autonomy_ceiling: 2
      }
  end

  defp get(input, key), do: Map.get(input, key) || Map.get(input, String.to_atom(key))
end
