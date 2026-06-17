defmodule Conveyor.Factory.PatchRiskWorkspaceResourcesTest do
  use Conveyor.DataCase, async: false

  alias Conveyor.Factory
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.PatchSet
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Project
  alias Conveyor.Factory.RiskAssessment
  alias Conveyor.Factory.RunAttempt
  alias Conveyor.Factory.RunSpec
  alias Conveyor.Factory.Slice
  alias Conveyor.Factory.StationRun
  alias Conveyor.Factory.WorkspaceMaterialization

  setup do
    project =
      Ash.create!(
        Project,
        %{name: "Patch sample", local_path: "/tmp/patch-sample", default_branch: "main"},
        domain: Factory
      )

    plan =
      Ash.create!(
        Plan,
        %{
          project_id: project.id,
          title: "Patch plan",
          intent: "Capture patch scope and workspaces.",
          source_document: "docs/plan.md",
          normalized_contract: %{"schema_version" => "conveyor.plan@1"},
          contract_sha256: digest("plan")
        },
        domain: Factory
      )

    epic =
      Ash.create!(Epic, %{plan_id: plan.id, title: "Patch epic", description: "Patch resources."},
        domain: Factory
      )

    slice =
      Ash.create!(Slice, %{epic_id: epic.id, title: "Patch slice", position: 1}, domain: Factory)

    run_spec = Ash.create!(RunSpec, run_spec_attrs(slice.id), domain: Factory)

    run_attempt =
      Ash.create!(
        RunAttempt,
        %{
          slice_id: slice.id,
          run_spec_id: run_spec.id,
          attempt_no: 1,
          base_commit: "abc123",
          status: :planned,
          outcome: :none,
          orchestrator_version: "conveyor@0.1.0",
          trace_id: "trace-patch"
        },
        domain: Factory
      )

    station_run =
      Ash.create!(
        StationRun,
        %{
          run_attempt_id: run_attempt.id,
          slice_id: slice.id,
          station: "implement",
          attempt_no: 1,
          station_spec_sha256: digest("station"),
          idempotency_key: "#{run_attempt.id}:implement:#{digest("station")}:1",
          input_sha256: digest("input")
        },
        domain: Factory
      )

    %{run_attempt: run_attempt, run_spec: run_spec, station_run: station_run}
  end

  test "patch sets record diff scope and locked-path touch flag", %{run_attempt: run_attempt} do
    patch_set =
      Ash.create!(
        PatchSet,
        %{
          run_attempt_id: run_attempt.id,
          base_commit: "abc123",
          patch_ref: "artifacts/patches/attempt-1.patch",
          patch_sha256: digest("patch"),
          changed_files: ["lib/conveyor/factory.ex", "priv/repo/migrations/1.exs"],
          added_files: ["priv/repo/migrations/1.exs"],
          deleted_files: [],
          renamed_files: [],
          lines_added: 42,
          lines_deleted: 3,
          touches_locked_paths: true,
          applies_cleanly: true
        },
        domain: Factory
      )

    assert patch_set.touches_locked_paths
    assert patch_set.lines_added == 42

    updated = Ash.update!(patch_set, %{applies_cleanly: false}, domain: Factory)
    refute updated.applies_cleanly
  end

  test "risk assessments compare planned and observed risk", %{run_attempt: run_attempt} do
    patch_set =
      Ash.create!(
        PatchSet,
        %{
          run_attempt_id: run_attempt.id,
          base_commit: "abc123",
          patch_ref: "artifacts/patches/attempt-1.patch",
          patch_sha256: digest("risk-patch"),
          changed_files: ["mix.exs"],
          lines_added: 4,
          lines_deleted: 1,
          touches_locked_paths: false,
          applies_cleanly: true
        },
        domain: Factory
      )

    risk =
      Ash.create!(
        RiskAssessment,
        %{
          run_attempt_id: run_attempt.id,
          patch_set_id: patch_set.id,
          planned_risk: "low",
          observed_risk: "high",
          reasons: ["dependency file changed"],
          touched_risk_domains: ["dependencies"],
          required_review_kinds: [:security, :architecture],
          required_gate_stages: ["dependency-audit", "full-test"]
        },
        domain: Factory
      )

    assert risk.observed_risk == "high"
    assert risk.required_review_kinds == [:security, :architecture]
  end

  test "workspace materializations track checkout and cleanup lifecycle", %{
    run_spec: run_spec,
    station_run: station_run
  } do
    workspace =
      Ash.create!(
        WorkspaceMaterialization,
        %{
          run_spec_id: run_spec.id,
          station_run_id: station_run.id,
          purpose: :implement,
          base_commit: "abc123",
          applied_patch_sha256: digest("patch"),
          path: "/tmp/conveyor/workspaces/attempt-1",
          container_id: "container-1",
          mount_mode: :read_write,
          head_tree_sha256: digest("tree"),
          cleanup_policy: :preserve_on_failure,
          cleanup_status: :pending
        },
        domain: Factory
      )

    assert workspace.purpose == :implement
    assert workspace.head_tree_sha256 == digest("tree")

    cleaned =
      Ash.update!(
        workspace,
        %{cleanup_status: :preserved, cleaned_at: DateTime.utc_now(:microsecond)},
        domain: Factory
      )

    assert cleaned.cleanup_status == :preserved
    assert cleaned.cleaned_at
  end

  defp run_spec_attrs(slice_id) do
    run_spec_sha256 = digest("run-spec")

    %{
      slice_id: slice_id,
      attempt_no: 1,
      run_spec_json_ref: "artifacts/run-specs/attempt-1.json",
      run_spec_sha256: run_spec_sha256,
      base_commit: "abc123",
      contract_lock_sha256: digest("contract-lock"),
      prompt_template_version: "implementation-prompt@1",
      agent_profile_snapshot: %{"adapter" => "pi"},
      policy_sha256: digest("policy"),
      diff_policy_sha256: digest("diff-policy"),
      test_pack_sha256: digest("test-pack"),
      station_plan: %{
        "schema_version" => "conveyor.station_plan@1",
        "stations" => [
          %{
            "key" => "implement",
            "input" => %{"run_spec_sha256" => run_spec_sha256},
            "output" => %{"run_spec_sha256" => run_spec_sha256}
          }
        ]
      },
      station_plan_sha256: digest("station-plan"),
      container_image_ref: "ghcr.io/conveyor/sample-python-runner:2026-06-01",
      container_image_digest: digest("image"),
      sandbox_profile: "verify",
      budget_sha256: digest("budget"),
      code_quality_profile: "standard",
      canary_suite_version: "canary@1"
    }
  end

  defp digest(label), do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, label), case: :lower)
end
