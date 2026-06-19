defmodule Conveyor.Eval.GoldenThread do
  @moduledoc """
  The Reference-Solution Golden Thread (B2): make a human plan drive the **whole**
  pipeline to a real verdict, today, for $0.

  `run_pipeline/1` takes a prepared bridge fixture (a lowered+augmented
  `station_plan` on a real `RunAttempt`, a sample git workspace) and runs:
  `RunSlice` over the `agent` station (deterministic `ReferenceSolution` applies the
  case's patch) → the `verify` station (real pytest via the F1 Toolchain Runner) →
  the gate (`run_gate_only!` on the real evidence). No injected fixtures.

  > **Divergence (§B2).** `station_plan` stands in for the eventual
  > `ContractLock + AgentBrief` forged by the P2-B Contract Forge; ContractLock /
  > approval / RoleView / TestPack are deferred. The lowering is pure and on-path
  > (`WorkGraphToStationPlan`); the contract content is crude (tracer-sanctioned).
  >
  > **Scope.** Like E1, the gate runs the `test_execution` stage, so the verdict is
  > exact for the real-execution discrimination set (known_good + the behavioral
  > mutants). The 5 static-stage mutants need the static gate stages wired with
  > their contexts — recorded as a follow-on (full `phase2_gate` is P2-B).
  >
  > **Standalone mix task** (`mix conveyor.eval.golden_thread`) is deferred: the
  > pipeline needs the DB-backed fixture chain (Slice/RunSpec/RunAttempt/…), proven
  > by `test/conveyor/eval/golden_thread_test.exs`, which also emits the metric.
  """

  alias Conveyor.Eval.{AgentStation, Scorecard, VerifyStation}
  alias Conveyor.Jobs.RunGate
  alias Conveyor.RunSlice

  @suite "golden_thread"
  @stations %{"agent" => AgentStation, "verify" => VerifyStation}
  @gate_stages [Conveyor.Gate.Stages.TestExecution]
  @gate_opts [
    gate_code_sha256: "sha256:bridge",
    policy_sha256: "sha256:bridge",
    contract_lock_sha256: "sha256:bridge"
  ]
  @calibration %{status: :valid, expected_failures: ["acceptance_red_on_base"]}

  @doc """
  Run plan→lower→station→agent→verify→gate for a prepared fixture. Returns
  `%{run_status, verification_status, gate_passed, findings}`.
  """
  @spec run_pipeline(map()) :: map()
  def run_pipeline(fixture) do
    slice =
      RunSlice.run!(fixture.run_attempt, station_modules: @stations, blob_root: fixture.blob_root)

    verification_result = slice.output["verification_result"]

    gate =
      RunGate.run_gate_only!(
        %{verification_result: verification_result, test_pack_calibration: @calibration},
        @gate_stages,
        @gate_opts
      )

    %{
      run_status: slice.status,
      verification_status: verification_result && verification_result["status"],
      gate_passed: gate.passed?,
      findings: gate.findings
    }
  end

  @doc "The `bridge_end_to_end` metric (blocking): known_good PASS ∧ all mutants FAIL ∧ traceability preserved."
  @spec metrics(map()) :: [map()]
  def metrics(report) do
    ok =
      report["known_good_passed"] == true and
        report["mutants_failed"] == report["mutants_total"] and
        report["traceability_preserved"] == true

    [
      Scorecard.metric("bridge_end_to_end", @suite, ok, true,
        blocking: true,
        detail:
          "known_good=#{report["known_good_passed"]}; mutants_failed=#{report["mutants_failed"]}/#{report["mutants_total"]}; traceability=#{report["traceability_preserved"]}"
      )
    ]
  end

  @doc "Write the bridge metric to the scorecard inputs dir."
  @spec emit!(map()) :: map()
  def emit!(report) do
    Scorecard.write_input!(@suite, metrics(report))
    report
  end
end
