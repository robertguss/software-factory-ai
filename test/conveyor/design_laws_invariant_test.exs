defmodule Conveyor.DesignLawsInvariantTest do
  use Conveyor.DataCase, async: false

  import Conveyor.FactoryFixtures, only: [create_artifact_run!: 1, temp_dir!: 1]

  alias Conveyor.AgentRunner
  alias Conveyor.AgentRunner.Capabilities
  alias Conveyor.Config.CommandSpec
  alias Conveyor.ContextScout
  alias Conveyor.DesignLaws
  alias Conveyor.Factory
  alias Conveyor.Factory.AgentBrief
  alias Conveyor.Factory.ContractLock
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.EventOutbox
  alias Conveyor.Factory.LedgerEvent
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Policy
  alias Conveyor.Factory.Project
  alias Conveyor.Factory.RunSpec
  alias Conveyor.Factory.Slice
  alias Conveyor.Factory.TestPack
  alias Conveyor.Factory.ToolInvocation
  alias Conveyor.PlanAuditor
  alias Conveyor.PlanContract
  alias Conveyor.PlanImport
  alias Conveyor.Policy.Engine
  alias Conveyor.Policy.NormalizedCommand
  alias Conveyor.Readiness
  alias Conveyor.Sandbox.DockerRunner
  alias Conveyor.Sandbox.Materialized
  alias Conveyor.SliceLifecycle
  alias Conveyor.ToolExecutor
  alias Conveyor.ToolMatrix
  alias Conveyor.Traceability

  @plan_fixture_dir Path.expand("../fixtures/plan_audit", __DIR__)
  @valid_plan Path.expand("../../docs/schemas/examples/conveyor.plan.valid.json", __DIR__)

  defmodule ObserveOnlyAdapter do
    @behaviour Conveyor.AgentRunner

    @impl true
    def capabilities do
      %Capabilities{
        streaming_events: true,
        pre_exec_command_policy: false,
        cancellation: :best_effort,
        diff_capture: :adapter_reported,
        cost_reporting: :none,
        mcp_support: true,
        slash_commands_enabled: true,
        structured_output: false,
        session_resume: false,
        known_limitations: []
      }
    end

    @impl true
    def run(_run_prompt, _workspace, _policy, _opts), do: {:error, :not_implemented}

    @impl true
    def cancel(_session_id), do: {:error, :not_implemented}
  end

  test "registry cross-references every design law to executable enforcement" do
    laws = DesignLaws.laws()

    assert Enum.map(laws, & &1.number) == Enum.to_list(1..10)

    for law <- laws do
      assert law.source_ref == "PHASE-0-1-IMPLEMENTATION-PLAN.md §3"
      assert law.statement =~ "No "
      assert law.invariant_test =~ "DesignLawsInvariantTest"
      assert law.feature_beads != []
      assert law.enforced_by != []
    end
  end

  test "law 1: tasks without acceptance criteria cannot pass handoff readiness" do
    result =
      "missing-ac.json"
      |> plan_contract!()
      |> persisted_plan!("law-1")
      |> import_and_audit!()

    assert result.decision == :blocked

    assert Enum.any?(
             result.findings,
             &(&1["message"] =~ "has no acceptance criteria")
           )
  end

  test "law 2: implementers cannot weaken locked tests or contract digests" do
    %{plan: plan, slice: slice} = create_handoff_slice!("law-2")
    create_locked_contract!(slice, plan, required_tests_sha256: digest("weakened-tests"))

    result = Readiness.check(slice, actor: "implementer")

    assert result.status == :blocked
    assert result.slice.state == :drafted
    assert Enum.any?(result.findings, &(&1.code == :required_tests_mismatch))
  end

  test "law 3: agent self-report alone is never trusted completion evidence" do
    invocation =
      Ash.create!(
        ToolInvocation,
        %{
          tool_name: "pytest",
          invocation_kind: "adapter_reported",
          command_spec: command_spec_map(["pytest", "-q"]),
          policy_profile: "verify",
          cwd: ".",
          env_keys: [],
          network_mode: :none,
          started_at: DateTime.utc_now(:microsecond),
          policy_decision: :allowed,
          status: :succeeded
        },
        domain: Factory
      )

    refute ToolExecutor.trusted_invocation?(invocation)
  end

  test "law 4: autonomy authority stays capped when measured control is absent" do
    snapshot =
      AgentRunner.agent_profile_snapshot(ObserveOnlyAdapter,
        adapter: "observe-only",
        model: "fake-observe"
      )

    assert snapshot["autonomy_ceiling"] == "L1"
    refute snapshot["capabilities"]["pre_exec_command_policy"]
    assert "no_pre_exec_interception" in snapshot["known_limitations"]
    assert "adapter_reported_diff_only" in snapshot["known_limitations"]
  end

  test "law 5: every material slice transition appends exactly one ledger event" do
    %{slice: slice} = create_handoff_slice!("law-5")
    create_brief!(slice, locked_by: "architect")

    assert slice_transition_events(slice.id) == []
    assert outbox_count() == 0

    transitioned = SliceLifecycle.transition!(slice, :approve, actor: "architect")

    assert transitioned.state == :approved
    assert [event] = slice_transition_events(slice.id)
    assert event.payload["previous_state"] == "drafted"
    assert event.payload["state"] == "approved"
    assert outbox_event_ids() == [event.id]
  end

  test "law 6: each run materializes one isolated Docker container" do
    repo = sample_git_repo!()

    fixture =
      create_artifact_run!(
        blob_root: temp_dir!("design-law-docker-blobs"),
        base_commit: repo.base_commit,
        local_path: repo.project_path
      )

    run_spec = get_by_id!(RunSpec, fixture.run_attempt.run_spec_id)
    parent = self()

    cmd = fn
      "docker", ["create" | args], _opts ->
        send(parent, {:docker_create, args})
        {"container-law-6\n", 0}

      "docker", ["start", "container-law-6"], _opts ->
        send(parent, :docker_start)
        {"container-law-6\n", 0}

      executable, args, opts ->
        System.cmd(executable, args, opts)
    end

    assert {:ok, %Materialized{} = materialized} =
             DockerRunner.materialize(run_spec,
               cmd: cmd,
               image_ref: "python:3.12-slim",
               workspace_root: temp_dir!("design-law-workspaces")
             )

    assert materialized.container_id == "container-law-6"
    assert_received {:docker_create, create_args}
    assert_received :docker_start
    refute_received {:docker_create, _extra_args}
    assert adjacent_args?(create_args, "--network", "none")
    assert adjacent_args?(create_args, "--security-opt", "no-new-privileges:true")
    assert "--privileged" not in create_args
    refute Enum.any?(create_args, &String.contains?(&1, "/var/run/docker.sock"))
  end

  test "law 7: context scouting records context without mutating source files" do
    %{project_path: project_path, slice: slice} = create_context_slice!("law-7")
    before_hashes = file_hashes!(project_path)

    pack = ContextScout.run!(slice)

    assert pack.relevant_files != []
    assert file_hashes!(project_path) == before_hashes
  end

  test "law 8: dangerous commands are blocked by default policy" do
    command = normalized_command(["git", "reset", "--hard", "HEAD"])
    policy = policy(allowlist: ["git"], denylist: ["git reset --hard"])

    assert %Engine.Decision{status: :blocked, reason: :denylisted} =
             Engine.evaluate!(policy, command)
  end

  test "law 9: orphan requirements and orphan slices block handoff traceability" do
    {:ok, contract_result} = PlanContract.load(@valid_plan)
    contract_result = append_open_untraced_requirement(contract_result)
    plan = persisted_plan!(contract_result, "law-9")
    PlanImport.import_requirements_and_decisions!(plan, contract_result)
    create_orphan_slice!(plan)

    result = Traceability.analyze_plan!(plan)

    assert result.status == :blocked
    assert result.coverage_summary["requirements"]["open"] == 1
    assert result.coverage_summary["slices"]["orphaned"] == 1

    assert Enum.any?(
             result.findings,
             &(&1["message"] == "Requirement REQ-ORPHAN is still open.")
           )

    assert Enum.any?(
             result.findings,
             &(&1["message"] =~ "has no source requirement, decision, bug, or improvement")
           )
  end

  test "law 10: Conveyor records external toolchain boundaries instead of bespoke substitutes" do
    law = DesignLaws.law!(10)
    image = ToolMatrix.default_toolchain_image()
    versions = ToolMatrix.latest_tested_versions()

    assert law.statement == "No bespoke tool empire."
    assert versions.docker_engine == ">= 24.0"
    assert ToolMatrix.sandbox_runner_version() =~ "docker"
    assert ToolMatrix.agent_adapter_version(:pi) =~ "agent_runner.pi"
    assert image.ref =~ "ghcr.io/"
    assert image.sbom_ref =~ "sbom"
  end

  defp plan_contract!(fixture) do
    fixture
    |> then(&Path.join(@plan_fixture_dir, &1))
    |> PlanContract.load()
    |> case do
      {:ok, contract_result} -> contract_result
      {:error, error} -> flunk("failed to load #{fixture}: #{inspect(error)}")
    end
  end

  defp import_and_audit!(%Plan{} = plan) do
    contract_result = %PlanContract.Result{
      source_path: plan.source_document,
      contract: plan.normalized_contract,
      contract_sha256: plan.contract_sha256
    }

    PlanImport.import_requirements_and_decisions!(plan, contract_result)
    PlanAuditor.audit_plan!(plan)
  end

  defp persisted_plan!(%PlanContract.Result{} = contract_result, label) do
    project =
      Ash.create!(
        Project,
        %{
          name: "Design laws #{label}",
          local_path: temp_dir!("design-laws-#{label}"),
          default_branch: "main",
          default_autonomy_level: 1
        },
        domain: Factory
      )

    Ash.create!(
      Plan,
      %{
        project_id: project.id,
        title: "Design laws #{label}",
        intent: Map.get(contract_result.contract, "goal", "Verify design law invariants."),
        source_document: contract_result.source_path,
        normalized_contract: contract_result.contract,
        contract_sha256: contract_result.contract_sha256
      },
      domain: Factory
    )
  end

  defp create_handoff_slice!(label) do
    project =
      Ash.create!(
        Project,
        %{
          name: "Design laws #{label}",
          local_path: temp_dir!("design-laws-#{label}"),
          default_branch: "main",
          default_autonomy_level: 1
        },
        domain: Factory
      )

    plan =
      Ash.create!(
        Plan,
        %{
          project_id: project.id,
          title: "Design laws #{label}",
          intent: "Verify design law #{label}.",
          source_document: "docs/#{label}.md",
          normalized_contract: %{"schema_version" => "conveyor.plan@1"},
          contract_sha256: digest("plan-#{label}"),
          status: :handoff_ready
        },
        domain: Factory
      )

    epic =
      Ash.create!(
        Epic,
        %{plan_id: plan.id, title: "Design laws #{label}", description: "Invariant test."},
        domain: Factory
      )

    slice =
      Ash.create!(
        Slice,
        %{
          epic_id: epic.id,
          title: "Design law #{label}",
          position: 1,
          autonomy_level: "L1",
          source_refs: ["REQ-#{String.upcase(label)}"]
        },
        domain: Factory
      )

    %{project: project, plan: plan, epic: epic, slice: slice}
  end

  defp create_locked_contract!(slice, plan, overrides) do
    brief = create_brief!(slice, locked_by: "architect")
    verification_commands = [command_spec_map(["mix", "test"])]
    test_pack_sha256 = digest("test-pack")

    Ash.create!(
      TestPack,
      %{
        slice_id: slice.id,
        version: 1,
        source_ref: "test/conveyor/design_laws_invariant_test.exs",
        test_pack_ref: "design-laws@v1",
        test_pack_sha256: test_pack_sha256,
        required_test_refs: ["test/conveyor/design_laws_invariant_test.exs"],
        acceptance_criteria_refs: ["AC-001"],
        mount_path: "/workspace/.conveyor/test-packs/design-laws",
        runner_command_specs: verification_commands,
        test_result_adapter: "Conveyor.TestResultAdapter.JUnit",
        locked_at: ~U[2026-06-18 00:00:00.000000Z],
        locked_by: "architect"
      },
      domain: Factory
    )

    attrs =
      %{
        slice_id: slice.id,
        agent_brief_id: brief.id,
        plan_contract_sha256: plan.contract_sha256,
        brief_sha256: brief.contract_sha256,
        acceptance_criteria_sha256: digest_value(brief.acceptance_criteria),
        required_tests_sha256: digest_value(brief.required_tests),
        test_pack_sha256: test_pack_sha256,
        verification_commands_sha256: digest_value(verification_commands),
        agents_md_sha256: digest("agents"),
        policy_sha256: digest("policy"),
        protected_path_globs: ["samples/tasks_service/**"],
        locked_at: ~U[2026-06-18 00:00:00.000000Z],
        locked_by: "architect"
      }
      |> Map.merge(Map.new(overrides))

    Ash.create!(ContractLock, attrs, domain: Factory)
  end

  defp create_context_slice!(label) do
    project_path = temp_dir!("design-laws-context-#{label}")
    File.mkdir_p!(Path.join(project_path, "tasks_service"))
    File.mkdir_p!(Path.join(project_path, "tests"))

    File.write!(
      Path.join(project_path, "tasks_service/main.py"),
      "def complete_task():\n    pass\n"
    )

    File.write!(
      Path.join(project_path, "tests/test_tasks.py"),
      "def test_complete_task():\n    pass\n"
    )

    File.write!(Path.join(project_path, "pyproject.toml"), "[project]\nname = \"design-laws\"\n")

    %{plan: plan, slice: slice} = create_handoff_slice!(label)

    project =
      plan
      |> Map.fetch!(:project_id)
      |> then(&get_by_id!(Project, &1))
      |> Ash.update!(%{local_path: project_path}, domain: Factory)

    slice =
      Ash.update!(
        slice,
        %{
          likely_files: ["tasks_service/main.py"],
          conflict_domains: ["tasks_api"]
        },
        domain: Factory
      )

    create_brief!(slice, locked_by: "architect")

    %{project: project, project_path: project_path, slice: slice}
  end

  defp create_brief!(slice, opts) do
    locked_by = Keyword.fetch!(opts, :locked_by)
    verification_commands = [command_spec_map(["mix", "test"])]

    Ash.create!(
      AgentBrief,
      %{
        slice_id: slice.id,
        version: 1,
        current_behavior: "The design law is not yet enforced.",
        desired_behavior: "The design law is enforced by executable tests.",
        key_interfaces: ["PATCH /tasks/{id}", "Conveyor.DesignLawsInvariantTest"],
        out_of_scope: ["Do not alter unrelated laws."],
        risk: "medium",
        acceptance_criteria: [acceptance_criterion()],
        required_tests: [required_test()],
        verification_commands: verification_commands,
        non_goals: [],
        locked_at: DateTime.utc_now(:microsecond),
        locked_by: locked_by,
        contract_sha256: digest("brief-#{slice.id}")
      },
      domain: Factory
    )
  end

  defp create_orphan_slice!(plan) do
    epic =
      Ash.create!(
        Epic,
        %{plan_id: plan.id, title: "Orphan source epic", description: "Traceability invariant."},
        domain: Factory
      )

    Ash.create!(
      Slice,
      %{
        epic_id: epic.id,
        title: "Unmapped cleanup",
        position: 99,
        source_refs: [],
        likely_files: ["app/main.py"],
        conflict_domains: ["tasks_api"]
      },
      domain: Factory
    )
  end

  defp append_open_untraced_requirement(%PlanContract.Result{} = contract_result) do
    contract =
      update_in(contract_result.contract, ["requirements"], fn requirements ->
        requirements ++
          [
            %{
              "key" => "REQ-ORPHAN",
              "text" => "Untraced requirements must block handoff readiness.",
              "risk" => "medium",
              "source_ref" => "plan.md#requirement-req-orphan",
              "status" => "open"
            }
          ]
      end)

    %PlanContract.Result{
      contract_result
      | contract: contract,
        contract_sha256: digest("open-untraced-requirement")
    }
  end

  defp sample_git_repo! do
    root = temp_dir!("design-law-docker-source")
    project_path = Path.join(root, "samples/tasks_service")
    File.mkdir_p!(Path.join(project_path, "tasks_service"))
    File.write!(Path.join(project_path, "pyproject.toml"), "[project]\nname = \"sample\"\n")
    File.write!(Path.join(project_path, "tasks_service/main.py"), "print('sample')\n")

    System.cmd("git", ["init"], cd: root, stderr_to_stdout: true)
    System.cmd("git", ["config", "user.email", "test@example.com"], cd: root)
    System.cmd("git", ["config", "user.name", "Test User"], cd: root)
    System.cmd("git", ["add", "."], cd: root, stderr_to_stdout: true)
    System.cmd("git", ["commit", "-m", "sample"], cd: root, stderr_to_stdout: true)

    {base_commit, 0} = System.cmd("git", ["rev-parse", "HEAD"], cd: root)

    %{root: root, project_path: project_path, base_commit: String.trim(base_commit)}
  end

  defp normalized_command(argv) do
    command_spec = %CommandSpec{
      key: List.first(argv),
      argv: argv,
      cwd: ".",
      profile: :verify,
      network: :none,
      env_allowlist: [],
      timeout_ms: 120_000
    }

    NormalizedCommand.normalize!(command_spec, workspace_root: temp_dir!("design-law-policy"))
  end

  defp policy(opts) do
    %Policy{
      name: "verify",
      profile: :verify,
      allowlist: Keyword.get(opts, :allowlist, []),
      denylist: Keyword.get(opts, :denylist, []),
      env_policy: Keyword.get(opts, :env_policy, %{"allowlist" => []}),
      network_policy: Keyword.get(opts, :network_policy, %{"default" => "none"}),
      budget_policy: %{},
      autonomy_ceiling: 1
    }
  end

  defp file_hashes!(root) do
    root
    |> Path.join("**/*")
    |> Path.wildcard()
    |> Enum.filter(&File.regular?/1)
    |> Map.new(fn path ->
      {Path.relative_to(path, root), File.read!(path) |> sha256()}
    end)
  end

  defp slice_transition_events(slice_id) do
    LedgerEvent
    |> Ash.read!(domain: Factory)
    |> Enum.filter(&(&1.slice_id == slice_id and &1.type == "slice.transitioned"))
    |> Enum.sort_by(&DateTime.to_unix(&1.occurred_at, :microsecond))
  end

  defp outbox_count do
    EventOutbox
    |> Ash.read!(domain: Factory)
    |> length()
  end

  defp outbox_event_ids do
    EventOutbox
    |> Ash.read!(domain: Factory)
    |> Enum.map(& &1.ledger_event_id)
  end

  defp acceptance_criterion do
    %{
      "id" => "AC-001",
      "text" => "Executable invariants fail when a design law is violated.",
      "kind" => "behavioral",
      "requirement_refs" => ["REQ-DESIGN-LAW"],
      "required_test_refs" => ["test/conveyor/design_laws_invariant_test.exs"],
      "evidence_status" => "missing",
      "evidence_refs" => []
    }
  end

  defp required_test do
    %{
      "ref" => "test/conveyor/design_laws_invariant_test.exs",
      "source_ref" => "test/conveyor/design_laws_invariant_test.exs",
      "acceptance_criteria_refs" => ["AC-001"],
      "locked" => true
    }
  end

  defp command_spec_map(argv) do
    %{
      "key" => List.first(argv),
      "argv" => argv,
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
  end

  defp adjacent_args?(args, key, value) do
    args
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.any?(&(&1 == [key, value]))
  end

  defp get_by_id!(resource, id) do
    resource
    |> Ash.read!(domain: Factory)
    |> Enum.find(&(&1.id == id)) ||
      raise ArgumentError, "#{inspect(resource)} #{id} was not found"
  end

  defp digest(label), do: "sha256:" <> sha256(label)
  defp digest_value(value), do: "sha256:" <> sha256(canonical_json(value))

  defp canonical_json(value) when is_map(value) do
    body =
      value
      |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
      |> Enum.map(fn {key, nested} ->
        Jason.encode!(to_string(key)) <> ":" <> canonical_json(nested)
      end)
      |> Enum.join(",")

    "{" <> body <> "}"
  end

  defp canonical_json(value) when is_list(value) do
    "[" <> Enum.map_join(value, ",", &canonical_json/1) <> "]"
  end

  defp canonical_json(value), do: Jason.encode!(value)

  defp sha256(content), do: Base.encode16(:crypto.hash(:sha256, content), case: :lower)
end
