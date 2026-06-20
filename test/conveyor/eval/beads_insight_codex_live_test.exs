defmodule Conveyor.Eval.BeadsInsightCodexLiveTest do
  @moduledoc """
  First Light — "the factory builds it itself."

  Drives the REAL Beads Insight plan through the same loop the deterministic tests
  use, but with the LIVE `Conveyor.AgentRunner.Codex` adapter (your ChatGPT/Codex
  subscription, ~$0 marginal): the STUB workspace (RED) + an implementation brief →
  Codex edits the workspace → real pytest (Toolchain Runner) → the now-proven
  deterministic gate. The agent's diff is graded by the exact same gate the
  reference solution PASSED and the mutants FAILED.

  Tagged `:live_agent` (excluded by default — real network + spend). Run:

      MIX_ENV=test PGPORT=5433 PGUSER=postgres PGPASSWORD=postgres \\
        mix test test/conveyor/eval/beads_insight_codex_live_test.exs --include live_agent

  The loop running to a verdict is the milestone; whether Codex one-shots the whole
  7-slice CLI is the *agent-capability* signal (a warn, not a loop blocker) — so the
  test asserts only that the loop completed, and reports the gate verdict.
  """
  use ExUnit.Case, async: false

  alias Conveyor.Eval.{BridgeFixtures, GoldenThread}

  @moduletag :live_agent
  @moduletag timeout: 900_000

  @sample Path.expand("../../../samples/beads_insight", __DIR__)
  @plan_path Path.join(@sample, "conveyor.plan.yml")
  @reference_patch "samples/beads_insight/.conveyor/canary/reference_full.patch"

  @brief """
  Implement the `br_insight` Python CLI in this repository so that the full test
  suite (`pytest -q`) passes. The package skeleton, the LOCKED data model
  (`src/br_insight/model.py` — DO NOT MODIFY IT), the complete acceptance test
  suite (`tests/`), the fixtures (`tests/fixtures/`), the golden output
  (`tests/golden/`), the plan (`conveyor.plan.yml`), and the project rules
  (`AGENTS.md`) are all already present. Read them.

  Implement these currently-stubbed modules (each raises NotImplementedError):
    - src/br_insight/loader.py   — parse a `.beads/issues.jsonl` export into an
      IssueGraph; build blocks/parent-child/related edge sets in canonical
      src->dst orientation from each record's `dependencies[]`
      ({depends_on_id, type}); on a malformed JSON line raise LoaderError carrying
      the 1-based line number.
    - src/br_insight/clock.py    — parse the injected `--as-of` RFC-3339 UTC value.
    - src/br_insight/report.py   — the `br_insight.report@1` JSON envelope,
      emitted byte-stable (sort_keys=False, separators=(",",":"), deterministically
      sorted arrays).
    - src/br_insight/commands/{ready,cycles,epics,velocity,digest}.py
    - src/br_insight/cli.py      — argparse dispatch (may already be partly wired):
      load the corpus (catch LoaderError -> exit 2 naming the line) BEFORE
      dispatching; `--format markdown|json` (unknown -> exit 2); cycles-found ->
      exit 1; success -> 0.

  HARD RULES (from AGENTS.md): the tool is read-only, performs NO network access,
  never invokes the live `br` binary, and `--as-of` is the ONLY source of time —
  never call datetime.now / utcnow / today / time.time in non-test code. The tests
  pin exact behaviors (cycle canonical rotation, weekly velocity bucket counts, the
  byte-stable digest golden, frozen corpus counts) — read each test to learn the
  precise expected output, then implement to match it exactly. Note: there is no
  venv in this workspace, so you cannot run pytest yourself; reason carefully from
  the test source. Make every test pass.
  """

  # A live Codex run easily exceeds the default 120s sandbox ownership timeout, so the
  # owning test process would lose its DB connection mid-run. Extend it (mirrors
  # LiftDuelLiveTest; custom setup instead of Conveyor.DataCase which hardcodes 120s).
  setup do
    pid =
      Ecto.Adapters.SQL.Sandbox.start_owner!(Conveyor.Repo,
        shared: true,
        ownership_timeout: :timer.minutes(60)
      )

    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    :ok
  end

  test "the factory builds Beads Insight: live Codex drives the loop to a gate verdict" do
    fixture =
      BridgeFixtures.sample_fixture!(
        label: "bi-codex",
        sample_path: @sample,
        plan_path: @plan_path,
        # ignored by Codex (it builds from the brief, not a patch); required by the station input
        patch_ref: @reference_patch,
        agent_adapter: Conveyor.AgentRunner.Codex,
        prompt_body: @brief
      )

    report = GoldenThread.run_pipeline(fixture)

    IO.puts("\n========== CODEX LIVE RUN — Beads Insight ==========")
    IO.puts("report: #{inspect(report, limit: :infinity)}")

    assert report.run_status == :succeeded,
           "the loop must drive agent -> verify -> gate without crashing; findings: #{inspect(report.findings)}"

    # --- DIFF-SCOPE (the bulletproof): prove Codex IMPLEMENTED the code rather than
    # touching the tests / locked model / golden to fake a green. Every source change
    # must land under src/br_insight/ (and never model.py). Build artifacts are filtered.
    ws = fixture.workspace.path
    base = fixture.base_commit
    System.cmd("git", ["-C", ws, "add", "--intent-to-add", "--", "."], stderr_to_stdout: true)

    {names, 0} =
      System.cmd("git", ["-C", ws, "diff", "--name-only", base, "--"], stderr_to_stdout: true)

    changed =
      names
      |> String.split("\n", trim: true)
      |> Enum.reject(
        &(String.contains?(&1, "__pycache__") or String.contains?(&1, ".pytest_cache") or
            String.ends_with?(&1, ".pyc") or String.ends_with?(&1, ".xml"))
      )

    IO.puts("codex changed files (filtered): #{inspect(changed)}")

    out_of_scope =
      Enum.reject(changed, fn f ->
        String.starts_with?(f, "src/br_insight/") and f != "src/br_insight/model.py"
      end)

    # Integrity invariant (hard): Codex must never touch tests, the locked model, the
    # golden, the plan, or AGENTS.md — regardless of whether it passed the gate.
    assert out_of_scope == [],
           "DIFF-SCOPE VIOLATION — Codex touched files outside src/br_insight/ (possible test/model/golden tamper): #{inspect(out_of_scope)}"

    assert "src/br_insight/loader.py" in changed,
           "expected Codex to actually implement the loader (not a no-op); changed: #{inspect(changed)}"

    IO.puts(
      ">>> DIFF-SCOPE OK — all #{length(changed)} source changes are under src/br_insight/ (model.py untouched). Codex implemented; it did not tamper."
    )

    if report.gate_passed do
      IO.puts(">>> 🎉 THE FACTORY BUILT IT — Codex's diff PASSED the gate on the real plan.")
    else
      IO.puts(
        ">>> Codex did not one-shot the whole 7-slice plan. verification=#{inspect(report.verification_status)}. " <>
          "This is the agent-capability signal (the loop + gate are already proven); findings above."
      )
    end
  end
end
