defmodule Conveyor.Stations.Implementer do
  @moduledoc "Production implementer station backed by an AgentRunner adapter."

  use Conveyor.Station, station: "implement"

  require Logger

  alias Conveyor.AgentRunner
  alias Conveyor.AgentRunner.ClaudeCode
  alias Conveyor.Budget.ReservationGate
  alias Conveyor.EmergencyStop.Store, as: EmergencyStopStore
  alias Conveyor.Factory

  alias Conveyor.Factory.{
    AgentSession,
    ContextPack,
    Epic,
    Plan,
    Policy,
    RunBudget,
    RunPrompt,
    Slice
  }

  alias Conveyor.PromptBuilder

  @impl Conveyor.Station
  @spec effects(map()) :: [atom() | map()]
  def effects(_input), do: [:file_write]

  @impl Conveyor.Station
  @spec run(map(), Conveyor.Station.Context.t()) :: {:ok, map()} | {:error, term()}
  def run(input, context) do
    # a3hf.2.1.3: reserve against the run budget BEFORE the agent call spends. A run with a
    # RunBudget whose envelope is gone is refused here rather than after burning the call; a run
    # with no RunBudget (most tests, un-provisioned runs) proceeds unchanged.
    case reserve_budget(context.run_attempt) do
      :ok -> do_run(input, context)
      {:deny, reason} -> refuse(context.run_attempt, reason)
    end
  end

  defp reserve_budget(run_attempt) do
    case run_budget_for(run_attempt.id) do
      nil ->
        :ok

      budget ->
        case ReservationGate.reserve(budget) do
          {:ok, _reservation} -> :ok
          {:deny, reason} -> {:deny, reason}
        end
    end
  end

  defp run_budget_for(run_attempt_id) do
    RunBudget
    |> Ash.read!(domain: Factory)
    |> Enum.find(&(&1.run_attempt_id == run_attempt_id))
  end

  defp refuse(run_attempt, reason) do
    Logger.warning(
      "Budget reservation refused before spend: run_attempt=#{run_attempt.id} reason=#{reason}"
    )

    # a3hf.2.1.4: an envelope breach durably trips the project's emergency stop, so the halt is
    # recorded and blocks restart rather than being a silent per-attempt refusal.
    trip_emergency_stop!(run_attempt)
    {:error, {:budget_refused, reason}}
  end

  defp trip_emergency_stop!(run_attempt) do
    project_id = project_id_for(run_attempt)

    EmergencyStopStore.trip!(:project, project_id,
      project_id: project_id,
      run_attempt_id: run_attempt.id,
      slice_id: run_attempt.slice_id,
      actor: "budget-guard",
      reason: "budget_envelope_breach",
      trace_id: run_attempt.trace_id
    )
  end

  defp project_id_for(run_attempt) do
    slice = Ash.get!(Slice, run_attempt.slice_id, domain: Factory)
    epic = Ash.get!(Epic, slice.epic_id, domain: Factory)
    Ash.get!(Plan, epic.plan_id, domain: Factory).project_id
  end

  defp do_run(input, context) do
    adapter = adapter_module(input)
    agent_session = agent_session!(context.run_attempt, input)
    run_prompt = Ash.get!(RunPrompt, agent_session.run_prompt_id, domain: Factory)
    workspace = %{path: get(input, "workspace_path"), base_commit: get(input, "base_commit")}

    by_attempt = get(input, "patch_refs_by_attempt")

    opts =
      [
        agent_session_id: agent_session.id,
        run_attempt_id: context.run_attempt.id,
        blob_root: get(input, "blob_root"),
        reference_patch: reference_patch_for(input, by_attempt, context.run_attempt.attempt_no),
        # a per-attempt reference run re-applies a different patch each attempt, so the
        # tree must be reset to base first (the prior attempt's patch is uncommitted).
        reset_workspace: is_map(by_attempt) and map_size(by_attempt) > 0,
        session_id: "run-#{context.run_attempt.id}"
      ]
      # Per-station model override (KTD6) and the adapter test exec seams, threaded from
      # station input. Only added when present — a nil value would override the adapter's
      # own default (model/exec) and break the run.
      |> maybe_put(:claude_code_model, get(input, "model"))
      |> maybe_put(:claude_code_exec, get(input, "claude_code_exec"))
      |> maybe_put(:codex_exec, get(input, "codex_exec"))

    case AgentRunner.run(adapter, run_prompt, workspace, policy(), opts) do
      {:ok, raw} ->
        artifact = %{
          kind: "agent_diff",
          media_type: "text/x-diff",
          projection_path: "agent/diff.patch",
          content_ref: raw.diff_ref
        }

        output =
          %{
            "adapter" => inspect(adapter),
            "diff_ref" => raw.diff_ref,
            "patch_set_id" => raw.metadata["patch_set_id"],
            artifacts: [artifact]
          }
          |> maybe_put_output("infra_error", raw.metadata["infra_error"])

        {:ok, output}

      {:error, reason} ->
        {:error, {:agent_failed, reason}}
    end
  end

  defp adapter_module(input) do
    case get(input, "adapter") do
      nil -> ClaudeCode
      module when is_atom(module) -> module
      name when is_binary(name) -> Module.concat([String.trim_leading(name, "Elixir.")])
    end
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp maybe_put_output(output, _key, nil), do: output
  defp maybe_put_output(output, key, value), do: Map.put(output, key, value)

  # Reference/test-only: pick the canned patch for THIS attempt from an attempt-keyed
  # map (string keys survive the run_spec JSON round-trip), falling back to the single
  # "patch_ref". Production Codex has no patch_ref and is unaffected.
  defp reference_patch_for(input, by_attempt, attempt_no)
       when is_map(by_attempt) and map_size(by_attempt) > 0 do
    Map.get(by_attempt, to_string(attempt_no)) || get(input, "patch_ref")
  end

  defp reference_patch_for(input, _by_attempt, _attempt_no), do: get(input, "patch_ref")

  defp agent_session!(run_attempt, input) do
    AgentSession
    |> Ash.read!(domain: Factory)
    |> Enum.find(&(&1.run_attempt_id == run_attempt.id)) ||
      create_agent_session!(run_attempt, input)
  end

  defp create_agent_session!(run_attempt, input) do
    context_pack = context_pack!(get(input, "context_pack_id"))

    run_prompt =
      PromptBuilder.build!(run_attempt.slice_id,
        context_pack: context_pack,
        prior_findings: get(input, "prior_findings"),
        agents_md_body: agents_md_excerpt(get(input, "workspace_path"))
      )

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
        # ponytail: a real coding agent cannot function with network :none — it must reach
        # its model API. Egress is open-bridge (ContainedExec); fs/env/non-root confinement
        # stays intact. Verify/gate sandboxes remain :none. Upgrade: allowlist-via-proxy.
        network_policy: %{"default" => "egress"},
        budget_policy: %{},
        autonomy_ceiling: 2
      }
  end

  # uh2g: thread the project's AGENTS.md into the prompt's bounded-trust "Project
  # Instructions" section. Missing file keeps the honest no-excerpt notice; a large
  # file is deterministically head-truncated so the prompt stays bounded and replayable.
  @agents_md_char_budget 8_000
  @no_agents_md "No AGENTS.md excerpt was provided."

  defp agents_md_excerpt(nil), do: @no_agents_md

  defp agents_md_excerpt(workspace_path) do
    case File.read(Path.join(workspace_path, "AGENTS.md")) do
      {:ok, content} -> bound_agents_md(content)
      {:error, _reason} -> @no_agents_md
    end
  end

  defp bound_agents_md(content) do
    if String.length(content) <= @agents_md_char_budget do
      content
    else
      String.slice(content, 0, @agents_md_char_budget) <>
        "\n\n…[AGENTS.md truncated to #{@agents_md_char_budget} chars]"
    end
  end

  defp get(input, key), do: Map.get(input, key) || Map.get(input, String.to_atom(key))
end
