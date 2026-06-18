defmodule ConveyorWeb.RunViewerLiveTest do
  use ConveyorWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Conveyor.EventOutboxRelay
  alias Conveyor.Factory
  alias Conveyor.Factory.AgentBrief
  alias Conveyor.Factory.CodeQualityRun
  alias Conveyor.Factory.ContextPack
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.Evidence
  alias Conveyor.Factory.GateHealth
  alias Conveyor.Factory.GateResult
  alias Conveyor.Factory.HumanApproval
  alias Conveyor.Factory.Incident
  alias Conveyor.Factory.PatchSet
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Project
  alias Conveyor.Factory.Review
  alias Conveyor.Factory.RunPrompt
  alias Conveyor.Factory.Slice
  alias Conveyor.FactoryFixtures
  alias Conveyor.Ledger

  setup do
    project =
      Ash.create!(
        Project,
        %{
          name: "Viewer sample",
          local_path: "/tmp/viewer-sample",
          default_branch: "main"
        },
        domain: Factory
      )

    plan =
      Ash.create!(
        Plan,
        %{
          project_id: project.id,
          title: "Viewer tracer plan",
          intent: "Exercise the run viewer projection.",
          source_document: "docs/viewer-plan.md",
          normalized_contract: %{"schema_version" => "conveyor.plan@1"},
          contract_sha256: "sha256:" <> String.duplicate("a", 64),
          status: :active
        },
        domain: Factory
      )

    epic =
      Ash.create!(
        Epic,
        %{
          plan_id: plan.id,
          title: "Viewer epic",
          description: "Render the work hierarchy.",
          risk: "low",
          status: :in_progress
        },
        domain: Factory
      )

    slice =
      Ash.create!(
        Slice,
        %{
          epic_id: epic.id,
          title: "Render ledger timeline",
          position: 1,
          state: :ready,
          risk: "medium",
          source_refs: ["REQ-VIEWER-001"]
        },
        domain: Factory
      )

    Ledger.write!(%{
      project_id: project.id,
      slice_id: slice.id,
      idempotency_key: "viewer:#{slice.id}:ready",
      type: "slice.ready",
      payload: %{"slice_id" => slice.id, "state" => "ready"},
      occurred_at: ~U[2026-01-02 03:04:05Z]
    })

    %{project: project, plan: plan, epic: epic, slice: slice}
  end

  test "renders a seeded slice and its ledger timeline", %{
    conn: conn,
    project: project,
    plan: plan,
    epic: epic,
    slice: slice
  } do
    {:ok, _view, html} = live(conn, ~p"/runs")

    assert html =~ "Run Viewer"
    assert html =~ project.name
    assert html =~ plan.title
    assert html =~ epic.title
    assert html =~ slice.title
    assert html =~ "REQ-VIEWER-001"
    assert html =~ "slice.ready"
    assert html =~ "viewer:#{slice.id}:ready"
    assert html =~ "2026-01-02 03:04:05 UTC"
  end

  test "updates when committed ledger events are published from the outbox", %{
    conn: conn,
    project: project,
    slice: slice
  } do
    {:ok, view, html} = live(conn, ~p"/runs")
    refute html =~ "slice.started"

    Ledger.write!(%{
      project_id: project.id,
      slice_id: slice.id,
      idempotency_key: "viewer:#{slice.id}:started",
      type: "slice.started",
      payload: %{"slice_id" => slice.id, "state" => "in_progress"},
      occurred_at: ~U[2026-01-02 03:05:06Z]
    })

    assert [_ | _] = EventOutboxRelay.publish_pending!()

    html = render(view)
    assert html =~ "slice.started"
    assert html =~ "viewer:#{slice.id}:started"
    assert html =~ "2026-01-02 03:05:06 UTC"
    assert html =~ "2 ledger events"
  end

  test "records not-integrated approval from the run viewer", %{conn: conn} do
    fixture =
      FactoryFixtures.create_artifact_run!(
        blob_root: FactoryFixtures.temp_dir!("viewer-approval")
      )

    {:ok, view, html} = live(conn, ~p"/runs")
    assert html =~ "Human approval"

    view
    |> element("form#human-approval-#{fixture.run_attempt.id}")
    |> render_submit(%{
      "approval" => %{
        "run_attempt_id" => fixture.run_attempt.id,
        "actor" => "human@example.test",
        "not_integrated" => "true",
        "rationale" => "Not merged."
      }
    })

    [approval] =
      HumanApproval
      |> Ash.read!(domain: Factory)
      |> Enum.filter(&(&1.run_attempt_id == fixture.run_attempt.id))

    assert approval.decision == :not_integrated
    assert render(view) =~ "not_integrated"
  end

  test "an invalid mark-external submission does not crash the live view", %{conn: conn} do
    fixture =
      FactoryFixtures.create_artifact_run!(
        blob_root: FactoryFixtures.temp_dir!("viewer-approval-invalid")
      )

    {:ok, view, _html} = live(conn, ~p"/runs")

    # Neither an external commit nor not_integrated -> record!/1 raises ArgumentError.
    # The LiveView must rescue it rather than crashing the process.
    view
    |> element("form#human-approval-#{fixture.run_attempt.id}")
    |> render_submit(%{
      "approval" => %{
        "run_attempt_id" => fixture.run_attempt.id,
        "actor" => "human@example.test",
        "external_commit" => "",
        "rationale" => ""
      }
    })

    assert Process.alive?(view.pid)

    assert [] ==
             HumanApproval
             |> Ash.read!(domain: Factory)
             |> Enum.filter(&(&1.run_attempt_id == fixture.run_attempt.id))
  end

  test "renders full run projection panels for the static report records", %{conn: conn} do
    %{project: project, run_attempt: run_attempt, station_run: station_run} =
      FactoryFixtures.create_artifact_run!(
        blob_root: FactoryFixtures.temp_dir!("viewer-full-run"),
        artifact_content: "full run artifact\n",
        projection_path: "manifest.json"
      )

    slice =
      Slice
      |> Ash.read!(domain: Factory)
      |> Enum.find(&(&1.id == run_attempt.slice_id))

    run_attempt =
      Ash.update!(
        run_attempt,
        %{
          status: :reported,
          outcome: :accepted,
          head_tree_sha256: digest("head-tree"),
          completed_at: ~U[2026-01-02 03:07:08Z]
        },
        domain: Factory
      )

    _station_run =
      Ash.update!(
        station_run,
        %{
          status: :succeeded,
          output_sha256: digest("station-output"),
          heartbeat_at: ~U[2026-01-02 03:06:07Z],
          completed_at: ~U[2026-01-02 03:06:30Z],
          artifact_refs: ["manifest.json"]
        },
        domain: Factory
      )

    brief = create_brief!(slice)

    context_pack =
      Ash.create!(
        ContextPack,
        %{
          slice_id: slice.id,
          scout_version: "context-scout@1",
          confidence: Decimal.new("0.91"),
          relevant_files: [
            %{"path" => "tasks_service/main.py", "reason" => "Defines task routes"}
          ],
          key_interfaces: ["PATCH /tasks/{id}"],
          existing_tests: ["tests/test_tasks.py"],
          risks: ["Preserve completed state."],
          suggested_validation: ["pytest -q"],
          code_quality_refs: ["quality/baseline.json"]
        },
        domain: Factory
      )

    Ash.create!(
      RunPrompt,
      %{
        slice_id: slice.id,
        brief_id: brief.id,
        context_pack_id: context_pack.id,
        template_version: "implementation-prompt@1",
        body: "# Implement\nUse bounded context.",
        body_sha256: digest("prompt-body"),
        policy_refs: ["policies/implement.yml"],
        memory_refs: [],
        output_schema_version: "conveyor.agent_output@1"
      },
      domain: Factory
    )

    patch_set =
      Ash.create!(
        PatchSet,
        %{
          run_attempt_id: run_attempt.id,
          base_commit: run_attempt.base_commit,
          patch_ref: "diff.patch",
          patch_sha256: digest("patch"),
          changed_files: ["tasks_service/main.py"],
          lines_added: 12,
          lines_deleted: 1
        },
        domain: Factory
      )

    Ash.create!(
      Evidence,
      %{
        run_attempt_id: run_attempt.id,
        patch_set_id: patch_set.id,
        changed_files: ["tasks_service/main.py"],
        diff_ref: "diff.patch",
        tool_invocation_refs: ["tool-invocations/pytest.json"],
        acceptance_results: [%{"id" => "AC-FULL-001", "status" => "passed"}],
        code_quality_result_ref: "quality/after.json",
        risks: [%{"risk" => "low"}],
        summary: "Acceptance evidence passed.",
        pr_body_ref: "pr_body.md"
      },
      domain: Factory
    )

    Ash.create!(
      CodeQualityRun,
      %{
        project_id: project.id,
        run_attempt_id: run_attempt.id,
        adapter: "CodeQualityAdapter.CodeScent",
        profile: "standard",
        baseline_ref: "quality/baseline.json",
        result_ref: "quality/after.json",
        findings_summary: %{"before" => 4, "after" => 2},
        new_high_risk_findings: 0,
        status: :succeeded
      },
      domain: Factory
    )

    Ash.create!(
      Review,
      %{
        run_attempt_id: run_attempt.id,
        reviewer_profile_id: Ash.UUID.generate(),
        review_kind: :general,
        rubric_version: "reviewer@1",
        dossier_sha256: digest("dossier"),
        reviewed_at: ~U[2026-01-02 03:08:09Z],
        decision: :accepted,
        recommendation: :merge,
        summary: "Looks ready.",
        findings: [],
        checks: [%{"name" => "acceptance", "passed" => true}]
      },
      domain: Factory
    )

    Ash.create!(
      GateResult,
      %{
        run_attempt_id: run_attempt.id,
        passed: true,
        stages: [%{"key" => "run_check", "status" => "passed"}],
        false_negative: false,
        gate_version: "gate@1",
        gate_code_sha256: digest("gate-code"),
        policy_sha256: digest("policy"),
        contract_lock_sha256: digest("contract-lock"),
        canary_suite_version: "canary@1"
      },
      domain: Factory
    )

    Ash.create!(
      GateHealth,
      %{
        project_id: project.id,
        freshness_key_sha256: digest("freshness"),
        gate_version: "gate@1",
        gate_code_sha256: digest("gate-code"),
        policy_sha256: digest("policy"),
        test_pack_sha256: digest("test-pack"),
        container_image_digest: digest("image"),
        code_quality_profile_sha256: digest("quality-profile"),
        canary_suite_version: "canary@1",
        runcheck_schema_version: "runcheck@1",
        last_run_ref: run_attempt.id,
        passed: true,
        false_negative_count: 0
      },
      domain: Factory
    )

    Ash.create!(
      Incident,
      %{
        project_id: project.id,
        slice_id: slice.id,
        run_attempt_id: run_attempt.id,
        severity: :warning,
        category: "policy_violation",
        description: "A denied command was attempted.",
        evidence_refs: ["tool-invocations/blocked.json"]
      },
      domain: Factory
    )

    {:ok, _view, html} = live(conn, ~p"/runs")

    assert html =~ "Run attempt"
    assert html =~ run_attempt.id
    assert html =~ "reported"
    assert html =~ "accepted"
    assert html =~ "Station status"
    assert html =~ "artifact"
    assert html =~ "2026-01-02 03:06:07 UTC"
    assert html =~ "ContextPack"
    assert html =~ "tasks_service/main.py"
    assert html =~ "pytest -q"
    assert html =~ "RunPrompt"
    assert html =~ "implementation-prompt@1"
    assert html =~ "policies/implement.yml"
    assert html =~ "Evidence"
    assert html =~ "AC-FULL-001"
    assert html =~ "pr_body.md"
    assert html =~ "CodeScent Delta"
    assert html =~ "quality/baseline.json"
    assert html =~ "quality/after.json"
    assert html =~ "Reviewer verdict"
    assert html =~ "Looks ready."
    assert html =~ "Gate stages"
    assert html =~ "run_check"
    assert html =~ "Canary status"
    assert html =~ "false negatives: 0"
    assert html =~ "Incidents"
    assert html =~ "policy_violation"
    assert html =~ "Export controls"
    assert html =~ "manifest.json"
    assert html =~ "dossier.md"
    assert html =~ "evidence.json"
  end

  defp create_brief!(slice) do
    Ash.create!(
      AgentBrief,
      %{
        slice_id: slice.id,
        version: 1,
        current_behavior: "Tasks can be listed.",
        desired_behavior: "Tasks can be completed.",
        key_interfaces: ["PATCH /tasks/{id}"],
        out_of_scope: ["Authentication"],
        acceptance_criteria: [
          %{
            "id" => "AC-FULL-001",
            "text" => "Completing a task returns the updated task.",
            "kind" => "behavioral",
            "requirement_refs" => ["REQ-VIEWER-FULL"],
            "required_test_refs" => ["tests/test_tasks.py"],
            "evidence_status" => "missing",
            "evidence_refs" => []
          }
        ],
        required_tests: [%{"ref" => "tests/test_tasks.py"}],
        verification_commands: [
          %{
            "key" => "pytest",
            "argv" => ["pytest", "-q"],
            "cwd" => ".",
            "profile" => "verify",
            "required" => true,
            "timeout_ms" => 120_000,
            "network" => "none",
            "env_allowlist" => [],
            "output_limit_bytes" => 2_000_000,
            "repeat" => 1,
            "flake_policy" => "fail_closed",
            "infra_retry_policy" => %{"max_retries" => 0, "retry_on" => []},
            "result_format" => "junit"
          }
        ],
        non_goals: [],
        locked_at: DateTime.utc_now(:microsecond),
        locked_by: "planner",
        contract_sha256: digest("brief")
      },
      domain: Factory
    )
  end

  defp digest(label) do
    "sha256:" <> Base.encode16(:crypto.hash(:sha256, label), case: :lower)
  end
end
