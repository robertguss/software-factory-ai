defmodule Conveyor.GateStagesRiskTest do
  use Conveyor.DataCase, async: false

  alias Conveyor.Factory
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.PatchSet
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Project
  alias Conveyor.Factory.ReviewPolicy
  alias Conveyor.Factory.RiskAssessment
  alias Conveyor.Factory.RunAttempt
  alias Conveyor.Factory.RunSpec
  alias Conveyor.Factory.Slice
  alias Conveyor.Gate.Stages.ObservedRisk

  test "fail-closed escalation blocks when observed risk exceeds planned risk" do
    result =
      ObservedRisk.run(%{
        planned_risk: "low",
        patch_set: %PatchSet{
          patch_ref: "artifacts/patches/attempt-1.patch",
          patch_sha256: digest("patch"),
          changed_files: ["mix.exs"],
          lines_added: 4,
          lines_deleted: 1
        },
        review_policy: %ReviewPolicy{
          escalation_policy: :fail_closed,
          default_required_review_kinds: [:general],
          risk_rules: [
            %{
              "when" => %{"dependency_changes" => true},
              "observed_risk" => "high",
              "required_review_kinds" => ["security", "architecture"],
              "required_gate_stages" => ["dependency-audit"],
              "require_human_approval" => false
            }
          ]
        }
      })

    assert result.status == :failed
    assert result.input_digests["planned_risk"] == "low"
    assert result.input_digests["observed_risk"] == "high"

    assert [finding] =
             Enum.filter(result.findings, &(&1["category"] == "observed_risk_exceeds_planned"))

    assert finding["severity"] == "blocking"
    assert finding["required_review_kinds"] == ["general", "security", "architecture"]
    assert finding["required_gate_stages"] == ["dependency-audit"]
    assert finding["touched_risk_domains"] == ["dependencies"]
  end

  test "human escalation blocks until human approval is present" do
    context = %{
      planned_risk: "medium",
      patch_set: %PatchSet{
        patch_ref: "artifacts/patches/attempt-1.patch",
        patch_sha256: digest("patch"),
        changed_files: ["lib/auth_api.ex"],
        lines_added: 12,
        lines_deleted: 1
      },
      review_policy: %ReviewPolicy{
        escalation_policy: :require_human,
        default_required_review_kinds: [:general],
        risk_rules: [
          %{
            "when" => %{"path_globs" => ["lib/*_api.ex"]},
            "observed_risk" => "high",
            "required_review_kinds" => ["security"],
            "require_human_approval" => true
          }
        ]
      }
    }

    result = ObservedRisk.run(context)

    assert result.status == :failed
    categories = Enum.map(result.findings, & &1["category"])
    assert "observed_risk_exceeds_planned" in categories
    assert "human_approval_required" in categories

    approved = ObservedRisk.run(Map.put(context, :human_approval_granted, true))
    assert approved.status == :passed
    refute Enum.any?(approved.findings, &(&1["category"] == "human_approval_required"))
  end

  test "allow-with-warning escalates review requirements without blocking the gate" do
    result =
      ObservedRisk.run(%{
        planned_risk: "low",
        patch_set: %PatchSet{
          patch_ref: "artifacts/patches/attempt-1.patch",
          patch_sha256: digest("patch"),
          changed_files: ["priv/repo/migrations/20260618101010_change.exs"],
          lines_added: 20,
          lines_deleted: 0
        },
        review_policy: %ReviewPolicy{
          escalation_policy: :allow_with_warning,
          default_required_review_kinds: [:general],
          risk_rules: [
            %{
              "when" => %{"migration_changes" => true},
              "observed_risk" => "medium",
              "required_review_kinds" => ["architecture"],
              "require_human_approval" => false
            }
          ]
        }
      })

    assert result.status == :passed
    assert [%{"severity" => "warning"}] = result.findings
  end

  test "matching risk rules are persisted as a RiskAssessment when resource IDs are present" do
    %{run_attempt: run_attempt} = fixture_graph()

    policy =
      Ash.create!(
        ReviewPolicy,
        %{
          project_id: run_attempt.slice.epic.plan.project_id,
          name: "default",
          default_required_review_kinds: [:general],
          escalation_policy: :fail_closed,
          risk_rules: [
            %{
              "when" => %{"path_globs" => ["priv/repo/migrations/**"]},
              "observed_risk" => "high",
              "required_review_kinds" => ["architecture"],
              "required_gate_stages" => ["contract-lock"],
              "require_human_approval" => false
            }
          ]
        },
        domain: Factory
      )

    patch_set =
      Ash.create!(
        PatchSet,
        %{
          run_attempt_id: run_attempt.id,
          base_commit: "abc123",
          patch_ref: "artifacts/patches/attempt-1.patch",
          patch_sha256: digest("risk-patch"),
          changed_files: ["priv/repo/migrations/20260618101010_change.exs"],
          lines_added: 4,
          lines_deleted: 1,
          touches_locked_paths: false,
          applies_cleanly: true
        },
        domain: Factory
      )

    result =
      ObservedRisk.run(%{
        planned_risk: "low",
        run_attempt: run_attempt,
        patch_set: patch_set,
        review_policy: policy
      })

    assert result.status == :failed

    [risk] =
      RiskAssessment
      |> Ash.read!(domain: Factory)
      |> Enum.filter(&(&1.run_attempt_id == run_attempt.id and &1.patch_set_id == patch_set.id))

    assert risk.planned_risk == "low"
    assert risk.observed_risk == "high"
    assert risk.touched_risk_domains == ["migrations"]
    assert risk.required_review_kinds == [:general, :architecture]
    assert risk.required_gate_stages == ["contract-lock"]
  end

  defp fixture_graph do
    project =
      Ash.create!(
        Project,
        %{name: "Risk sample", local_path: "/tmp/risk-sample", default_branch: "main"},
        domain: Factory
      )

    plan =
      Ash.create!(
        Plan,
        %{
          project_id: project.id,
          title: "Risk plan",
          intent: "Assess risk.",
          source_document: "docs/plan.md",
          normalized_contract: %{"schema_version" => "conveyor.plan@1"},
          contract_sha256: digest("plan")
        },
        domain: Factory
      )

    epic =
      Ash.create!(Epic, %{plan_id: plan.id, title: "Risk epic", description: "Risk resources."},
        domain: Factory
      )

    slice =
      Ash.create!(Slice, %{epic_id: epic.id, title: "Risk slice", position: 1}, domain: Factory)

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
          trace_id: "trace-risk"
        },
        domain: Factory,
        load: [slice: [epic: [plan: :project]]]
      )

    %{run_attempt: run_attempt}
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
