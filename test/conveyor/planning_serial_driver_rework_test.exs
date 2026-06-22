defmodule Conveyor.Planning.SerialDriverReworkTest do
  # M2(b): SerialDriver.run_one! with `rework: true` delegates a non-accepted slice to
  # AttemptLoop, which reworks within a budget (driving the REAL ReworkSynthesizer +
  # RunSpecForge.forge_retry! retry path) instead of parking + halting the plan. Default
  # CI test: the slice run/gate/finalize are deterministic fakes (fail attempt 1, pass
  # attempt 2) — no venv/pytest — but the rework collaborators run for real.
  use Conveyor.DataCase, async: false

  alias Conveyor.Factory
  alias Conveyor.Factory.{Epic, Plan, Project, RunAttempt, Slice}
  alias Conveyor.Gate
  alias Conveyor.PlanContract
  alias Conveyor.Planning.SerialDriver

  @sample Path.expand("../../samples/beads_insight", __DIR__)
  @plan_path Path.join(@sample, "conveyor.plan.yml")
  @slice "SLICE-001"

  test "rework: a slice that fails attempt 1 recovers on rework, instead of parking the plan" do
    fixture = fixture!("serial-rework")
    slice = Map.fetch!(fixture.slices_by_stable_key, @slice)

    result =
      SerialDriver.run!(
        %{work_graph: fixture.work_graph, selected_slice_ids: [@slice]},
        slices_by_stable_key: fixture.slices_by_stable_key,
        run_spec_opts: [plan_path: @plan_path, blob_root: fixture.blob_root],
        actor: "serial-rework-test",
        # opt-in rework, bounded to one retry
        rework: true,
        max_attempts: 2,
        # deterministic fail-then-pass at the slice/gate/finalize seams; the REAL
        # AttemptLoop rework path (synthesize -> forge retry spec -> create retry
        # attempt) runs between attempts.
        run_slice: fn _attempt ->
          %{status: :succeeded, output: %{"verification_result" => %{}}}
        end,
        run_gate: fn _run_spec, attempt, _slice_result ->
          if attempt.attempt_no == 1 do
            gate_result(false, [
              %{
                "category" => "acceptance_mapping",
                "severity" => "blocking",
                "stage" => "verify",
                "message" => "AC-001 was not met.",
                "acceptance_criterion_id" => "AC-001",
                "evidence_status" => "not_met"
              }
            ])
          else
            gate_result(true, [])
          end
        end,
        finalize_gate: fn gate, _run_spec, attempt ->
          if gate.passed? do
            %{
              run_attempt:
                Ash.update!(attempt, %{status: :gated, outcome: :accepted}, domain: Factory)
            }
          else
            rework =
              Ash.update!(
                attempt,
                %{status: :needs_rework, outcome: :needs_rework, failure_category: "gate_failed"},
                domain: Factory
              )

            %{
              run_attempt: rework,
              slice: Ash.update!(slice, %{state: :needs_rework}, domain: Factory)
            }
          end
        end,
        # don't touch a real workspace in this deterministic test
        advance_workspace_base: fn _run_spec, _slice_key, _final -> :ok end
      )

    # The plan PASSED — the slice recovered via rework rather than parking + halting.
    assert result.status == :passed, inspect(result.events, pretty: true)
    [event] = result.events
    assert event["status"] == "passed"
    assert event["run_attempt_outcome"] == :accepted
    assert event["gate_result"] == "eventual_pass"
    assert event["attempt_count"] == 2

    # The REAL rework path created a second attempt that was accepted.
    attempts =
      RunAttempt |> Ash.read!(domain: Factory) |> Enum.filter(&(&1.slice_id == slice.id))

    assert Enum.map(attempts, & &1.attempt_no) |> Enum.sort() == [1, 2]
    retry = Enum.find(attempts, &(&1.attempt_no == 2))
    assert retry.outcome == :accepted
  end

  test "rework: false — a failing slice still parks + halts (legacy single-attempt path)" do
    fixture = fixture!("serial-no-rework")
    slice = Map.fetch!(fixture.slices_by_stable_key, @slice)

    result =
      SerialDriver.run!(
        %{work_graph: fixture.work_graph, selected_slice_ids: [@slice]},
        slices_by_stable_key: fixture.slices_by_stable_key,
        run_spec_opts: [plan_path: @plan_path, blob_root: fixture.blob_root],
        actor: "serial-no-rework-test",
        # rework is ON by default now — opt out to exercise the single-attempt path
        rework: false,
        run_slice: fn _attempt ->
          %{status: :succeeded, output: %{"verification_result" => %{}}}
        end,
        run_gate: fn _run_spec, _attempt, _slice_result -> gate_result(false, []) end,
        finalize_gate: fn _gate, _run_spec, attempt ->
          %{
            run_attempt:
              Ash.update!(attempt, %{status: :needs_rework, outcome: :needs_rework},
                domain: Factory
              )
          }
        end,
        advance_workspace_base: fn _r, _s, _f -> :ok end
      )

    assert result.status == :halted
    assert [%{"status" => "parked"}] = result.events
    # exactly one attempt — no rework
    assert RunAttempt |> Ash.read!(domain: Factory) |> Enum.count(&(&1.slice_id == slice.id)) == 1
  end

  defp gate_result(passed?, findings) do
    %Gate.Result{
      status: if(passed?, do: :passed, else: :failed),
      passed?: passed?,
      stages: [],
      findings: findings,
      gate_result_attrs: %{}
    }
  end

  defp fixture!(label) do
    {:ok, contract_result} = PlanContract.load(@plan_path)
    blob_root = temp_dir!("#{label}-blobs")

    project =
      Ash.create!(
        Project,
        %{
          name: "Beads Insight",
          local_path: git_workspace!(label),
          default_branch: "main",
          default_autonomy_level: 2
        },
        domain: Factory
      )

    plan =
      Ash.create!(
        Plan,
        %{
          project_id: project.id,
          title: "Beads Insight plan",
          intent: contract_result.contract["goal"],
          source_document: contract_result.source_path,
          normalized_contract: contract_result.contract,
          contract_sha256: contract_result.contract_sha256,
          status: :handoff_ready
        },
        domain: Factory
      )

    epic =
      Ash.create!(Epic, %{plan_id: plan.id, title: "epic", description: "M2(b)."},
        domain: Factory
      )

    slices_by_stable_key =
      contract_result.contract
      |> Map.fetch!("slices")
      |> Enum.with_index(1)
      |> Map.new(fn {sc, position} ->
        slice =
          Ash.create!(
            Slice,
            %{
              epic_id: epic.id,
              title: sc["title"],
              position: position,
              risk: "medium",
              autonomy_level: sc["autonomy_ceiling"],
              source_refs: sc["requirement_refs"],
              likely_files: sc["likely_files"],
              conflict_domains: sc["conflict_domains"]
            },
            domain: Factory
          )

        {sc["key"], slice}
      end)

    %{
      blob_root: blob_root,
      slices_by_stable_key: slices_by_stable_key,
      work_graph: work_graph(contract_result.contract)
    }
  end

  defp work_graph(contract) do
    %{
      "schema_version" => "conveyor.work_graph@2",
      "slices" =>
        Enum.map(contract["slices"], fn s ->
          %{
            "stable_key" => s["key"],
            "title" => s["title"],
            "requirement_refs" => s["requirement_refs"],
            "likely_files" => s["likely_files"],
            "conflict_domains" => s["conflict_domains"]
          }
        end),
      "work_dependencies" => []
    }
  end

  defp git_workspace!(label) do
    path = temp_dir!(label)

    {_, 0} =
      System.cmd("rsync", [
        "-a",
        "--exclude",
        ".venv",
        "--exclude",
        ".pytest_cache",
        "--exclude",
        "__pycache__",
        "--exclude",
        ".git",
        @sample <> "/",
        path <> "/"
      ])

    git!(path, ["init", "-b", "main"])
    git!(path, ["config", "user.email", "conveyor@example.test"])
    git!(path, ["config", "user.name", "Conveyor Test"])
    git!(path, ["add", "."])
    git!(path, ["commit", "-m", "base"])
    path
  end

  defp git!(path, args) do
    {output, 0} = System.cmd("git", ["-C", path | args], stderr_to_stdout: true)
    String.trim(output)
  end

  defp temp_dir!(label) do
    path = Path.join(System.tmp_dir!(), "conveyor-#{label}-#{System.unique_integer([:positive])}")
    File.rm_rf!(path)
    File.mkdir_p!(path)
    path
  end
end
