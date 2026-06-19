defmodule Conveyor.Eval.BridgeFixtures do
  @moduledoc """
  Test fixtures for the Reference-Solution Golden Thread (B2): a sample-backed git
  workspace plus the full Ash chain (Project → … → AgentSession) carrying the pure
  lowered `station_plan` (augmented with runtime params on the agent/verify station
  inputs). Shared by the ReferenceSolution conformance test and the Golden Thread
  end-to-end test. Mirrors the chain in `agent_runner_fake_test.exs`.
  """

  alias Conveyor.Eval.{CompilerProperties, WorkGraphToStationPlan}
  alias Conveyor.Factory

  alias Conveyor.Factory.{
    AgentBrief,
    AgentSession,
    ContextPack,
    Epic,
    Plan,
    Policy,
    Project,
    RunAttempt,
    RunPrompt,
    RunSpec,
    Slice
  }

  alias Conveyor.Planning.WorkGraphLowering

  @sample Path.expand("../../samples/tasks_service", __DIR__)
  @plan_path Path.join(@sample, "conveyor.plan.yml")

  @doc """
  Build a bridge fixture. `opts`:
    * `:patch_ref` — repo-root-relative canary patch the agent will apply (required
      for the agent station; defaults to known_good).
    * `:break_with` — a repo-root-relative mutant patch applied **and committed** so
      the workspace starts broken (base_commit = broken). The R5 lift duel uses this
      to make each mutant a broken→fix task (the bare sample is correct/green).
    * `:adapter_name` — recorded on the fixture (default "reference_solution").
    * `:label` — temp-dir label.
  """
  @spec sample_fixture!(keyword()) :: map()
  def sample_fixture!(opts \\ []) do
    label = Keyword.get(opts, :label, "bridge")

    patch_ref =
      Keyword.get(opts, :patch_ref, "samples/tasks_service/.conveyor/canary/known_good.patch")

    adapter_name = Keyword.get(opts, :adapter_name, "reference_solution")

    workspace_path = git_sample_workspace!(label, Keyword.get(opts, :break_with))
    base_commit = git!(workspace_path, ["rev-parse", "HEAD"])
    blob_root = Conveyor.FactoryFixtures.temp_dir!("#{label}-blobs")

    run_spec_sha256 = digest("run-spec-#{label}")

    station_plan =
      augmented_station_plan(run_spec_sha256, workspace_path, base_commit, patch_ref, blob_root)

    project =
      Ash.create!(
        Project,
        %{name: "Bridge sample", local_path: workspace_path, default_branch: "main"},
        domain: Factory
      )

    plan =
      Ash.create!(
        Plan,
        %{
          project_id: project.id,
          title: "Bridge plan",
          intent: "Drive the full pipeline to a verdict.",
          source_document: "docs/bridge.md",
          normalized_contract: %{"schema_version" => "conveyor.plan@1"},
          contract_sha256: digest("plan")
        },
        domain: Factory
      )

    epic =
      Ash.create!(Epic, %{plan_id: plan.id, title: "Bridge epic", description: "Bridge."},
        domain: Factory
      )

    slice =
      Ash.create!(Slice, %{epic_id: epic.id, title: "Bridge slice", position: 1}, domain: Factory)

    brief =
      Ash.create!(
        AgentBrief,
        %{
          slice_id: slice.id,
          version: 1,
          current_behavior: "Sample tasks service.",
          desired_behavior: "Apply the reference solution.",
          key_interfaces: ["tasks_service.main"],
          acceptance_criteria: [acceptance_criterion()],
          verification_commands: [command_spec()],
          locked_at: DateTime.utc_now(:microsecond),
          locked_by: "planner",
          contract_sha256: digest("brief")
        },
        domain: Factory
      )

    context_pack =
      Ash.create!(
        ContextPack,
        %{
          slice_id: slice.id,
          scout_version: "context-scout@1",
          confidence: Decimal.new("0.90"),
          relevant_files: [%{"path" => "tasks_service/main.py", "reason" => "Service."}],
          key_interfaces: ["tasks_service.main"],
          suggested_validation: ["pytest -q"],
          code_quality_refs: []
        },
        domain: Factory
      )

    run_prompt =
      Ash.create!(
        RunPrompt,
        %{
          slice_id: slice.id,
          brief_id: brief.id,
          context_pack_id: context_pack.id,
          template_version: "implementation-prompt@1",
          body: "Apply the reference solution to the sample.",
          body_sha256: digest("bridge-prompt"),
          output_schema_version: "conveyor.agent_output@1"
        },
        domain: Factory
      )

    run_spec =
      Ash.create!(RunSpec, run_spec_attrs(slice.id, base_commit, run_spec_sha256, station_plan),
        domain: Factory
      )

    run_attempt =
      Ash.create!(
        RunAttempt,
        %{
          slice_id: slice.id,
          run_spec_id: run_spec.id,
          attempt_no: 1,
          base_commit: base_commit,
          status: :running,
          outcome: :none,
          orchestrator_version: "conveyor@0.1.0",
          trace_id: "trace-bridge"
        },
        domain: Factory
      )

    agent_session =
      Ash.create!(
        AgentSession,
        %{
          run_attempt_id: run_attempt.id,
          run_prompt_id: run_prompt.id,
          agent_profile_id: Ash.UUID.generate(),
          role: :implementer,
          base_commit: base_commit,
          status: :running
        },
        domain: Factory
      )

    %{
      adapter_name: adapter_name,
      agent_session: agent_session,
      blob_root: blob_root,
      policy: policy(),
      run_attempt: run_attempt,
      run_prompt: run_prompt,
      run_spec: run_spec,
      slice: slice,
      base_commit: base_commit,
      patch_ref: patch_ref,
      plan_path: @plan_path,
      workspace: %{path: workspace_path, base_commit: base_commit}
    }
  end

  @doc "The pure lowered station_plan augmented with runtime params on the station inputs."
  def augmented_station_plan(run_spec_sha256, workspace_path, base_commit, patch_ref, blob_root) do
    {cand, spec} = CompilerProperties.candidate_fixture(1)
    {:ok, work_graph} = WorkGraphLowering.lower(cand, spec)
    {:ok, base} = WorkGraphToStationPlan.lower(work_graph, run_spec_sha256)

    stations =
      Enum.map(base["stations"], fn station ->
        extra =
          case station["key"] do
            "agent" ->
              %{
                "workspace_path" => workspace_path,
                "base_commit" => base_commit,
                "patch_ref" => patch_ref,
                "blob_root" => blob_root
              }

            "verify" ->
              %{"workspace_path" => workspace_path, "plan_path" => @plan_path}

            _ ->
              %{}
          end

        Map.update!(station, "input", &Map.merge(&1, extra))
      end)

    %{base | "stations" => stations}
  end

  defp git_sample_workspace!(label, break_with) do
    path = Conveyor.FactoryFixtures.temp_dir!(label)

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
    maybe_break!(path, break_with)
    path
  end

  # Apply and commit a mutant so the workspace starts broken (base_commit = broken).
  defp maybe_break!(_path, nil), do: :ok

  defp maybe_break!(path, patch_ref) do
    patch_abs = Path.expand(patch_ref, File.cwd!())

    {_, 0} =
      System.cmd("patch", ["-p3", "-f", "-d", path, "-i", patch_abs], stderr_to_stdout: true)

    git!(path, ["add", "."])
    git!(path, ["commit", "-m", "break: " <> Path.basename(patch_ref)])
  end

  defp git!(path, args) do
    {output, 0} = System.cmd("git", ["-C", path | args], stderr_to_stdout: true)
    String.trim(output)
  end

  defp policy do
    %Policy{
      name: "implement",
      profile: :implement,
      allowlist: ["reference"],
      denylist: [],
      env_policy: %{"allowlist" => []},
      network_policy: %{"default" => "none"},
      budget_policy: %{},
      autonomy_ceiling: 2
    }
  end

  defp run_spec_attrs(slice_id, base_commit, run_spec_sha256, station_plan) do
    %{
      slice_id: slice_id,
      attempt_no: 1,
      run_spec_json_ref: "artifacts/run-specs/bridge.json",
      run_spec_sha256: run_spec_sha256,
      base_commit: base_commit,
      contract_lock_sha256: digest("contract-lock"),
      prompt_template_version: "implementation-prompt@1",
      agent_profile_snapshot: %{"adapter" => "reference_solution"},
      policy_sha256: digest("policy"),
      diff_policy_sha256: digest("diff-policy"),
      test_pack_sha256: digest("test-pack"),
      station_plan: station_plan,
      station_plan_sha256: Conveyor.CanonicalJson.digest(station_plan),
      container_image_ref: "ghcr.io/conveyor/sample-python-runner:2026-06-17",
      container_image_digest: digest("image"),
      sandbox_profile: "verify",
      budget_sha256: digest("budget"),
      code_quality_profile: "standard",
      canary_suite_version: "canary@1"
    }
  end

  defp acceptance_criterion do
    %{
      "id" => "AC-001",
      "text" => "Completing an unknown task returns 404.",
      "kind" => "behavioral",
      "requirement_refs" => ["REQ-001"],
      "required_test_refs" => ["tests/test_tasks_api.py::test_complete_unknown_task_returns_404"],
      "evidence_status" => "missing",
      "evidence_refs" => []
    }
  end

  defp command_spec do
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
  end

  defp digest(label), do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, label), case: :lower)
end
