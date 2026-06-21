defmodule Conveyor.Planning.PlanFoundry.Drafter do
  @moduledoc """
  Behaviour for the generative first step of ADR-27 (Plan Foundry): turn a prose
  intent into a structured `conveyor.plan@1` contract map.

  The drafter is the ONE non-deterministic actor in plan authoring. It is isolated
  behind this seam so the rest of `Conveyor.Planning.PlanFoundry.draft/2` (the
  structural audit + interrogation) stays pure and testable, and so the drafter
  (author) is a distinct actor from the critic and the downstream implementer —
  the separation of duties ADR-27 requires.

  Implementations: `Conveyor.Planning.PlanFoundry.CodexDrafter` (live, the next
  slice) and test fakes that inject canned plans.
  """

  @callback draft_plan(intent :: String.t(), opts :: keyword()) ::
              {:ok, map()} | {:error, term()}
end
