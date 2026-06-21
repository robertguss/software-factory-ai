defmodule Conveyor.Gate.MidflightCheck do
  @moduledoc """
  ADR-24 — conductor-mediated, read-only in-loop verification.

  A cheap, deterministic, **advisory** check the conductor can offer an
  implementer *during* generation ("am I on track?") instead of making it wait for
  the full gate at the end. It runs only the cheap **static** gate stages — diff
  scope, contract lock, secret safety, acceptance mapping — which tell the agent
  what the contract already asks of it.

  Two safety properties hold by construction:

    * **It is a read, not authority.** It returns a report and mutates nothing —
      no `GateResult` is persisted, no slice/run-attempt transitions. The
      authoritative gate still runs in full at finalization (the determinism
      boundary, ADR-06/07).
    * **The hidden oracle is never exposed.** Mutation, reference-solution
      survival, and red-team are *not gate stages* (they live in the eval surface),
      so the agent cannot mine them through this channel; and the expensive
      execution stages (build/test/canary) are excluded from the default subset to
      keep the check cheap and free of the test-execution oracle.
  """

  # Cheap static stages safe + useful to show the implementer mid-flight.
  @default_stages [
    Conveyor.Gate.Stages.DiffScope,
    Conveyor.Gate.Stages.ContractLock,
    Conveyor.Gate.Stages.SecretSafety,
    Conveyor.Gate.Stages.AcceptanceMapping
  ]

  @type report :: %{
          advisory: true,
          on_track?: boolean(),
          findings: [map()],
          stages_run: [String.t()]
        }

  @doc "The default mid-flight stage subset (cheap, static, no hidden oracle)."
  @spec default_stages() :: [module()]
  def default_stages, do: @default_stages

  @doc """
  Run the advisory mid-flight check over a gate context. Returns a read-only
  report; nothing is persisted or transitioned. `opts[:stages]` overrides the
  subset (used in tests / for narrower checks).
  """
  @spec run(map(), keyword()) :: report()
  def run(context, opts \\ []) when is_map(context) and is_list(opts) do
    stages = Keyword.get(opts, :stages, @default_stages)

    # Invoke each stage's behaviour directly — advisory only. Unlike the real
    # gate, this builds no GateResult, persists nothing, and transitions nothing.
    results = Enum.map(stages, fn module -> module.run(context, []) end)
    findings = Enum.flat_map(results, &Map.get(&1, :findings, []))
    on_track? = Enum.all?(results, &(Map.get(&1, :status) != :failed))

    %{
      advisory: true,
      on_track?: on_track?,
      findings: findings,
      stages_run: Enum.map(stages, &stage_label/1)
    }
  end

  defp stage_label(module) do
    module |> Module.split() |> List.last() |> Macro.underscore()
  end
end
