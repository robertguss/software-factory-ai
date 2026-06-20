defmodule Conveyor.Planning.PlanFoundry.CodexDrafter do
  @moduledoc """
  Live `Conveyor.Planning.PlanFoundry.Drafter` backed by the Codex agent (ADR-27).

  NOT YET WIRED. The next slice builds the versioned plan-drafting prompt (the
  intent plus the `conveyor.plan@1` output schema and the project's non-goals /
  separation-of-duties framing), calls `Conveyor.AgentRunner.Codex`, and parses
  the agent's result into a contract map. Until then it returns
  `{:error, :not_implemented}` so the deterministic `PlanFoundry.draft/2` spine is
  exercised through an injected drafter rather than a live agent.
  """

  @behaviour Conveyor.Planning.PlanFoundry.Drafter

  @impl true
  def draft_plan(_intent, _opts), do: {:error, :not_implemented}
end
