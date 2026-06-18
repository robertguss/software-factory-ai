defmodule Conveyor.AgentRunnerTest do
  use Conveyor.DataCase, async: false

  alias Conveyor.AgentRunner
  alias Conveyor.AgentRunner.Capabilities
  alias Conveyor.Factory
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Project
  alias Conveyor.Factory.RunSpec
  alias Conveyor.Factory.Slice

  defmodule ObserveOnlyAdapter do
    @behaviour Conveyor.AgentRunner

    @impl true
    def capabilities do
      %{
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

  defmodule PolicyControlledAdapter do
    @behaviour Conveyor.AgentRunner

    @impl true
    def capabilities do
      %Capabilities{
        streaming_events: true,
        pre_exec_command_policy: true,
        cancellation: :hard,
        diff_capture: :git_diff,
        cost_reporting: :estimated,
        mcp_support: false,
        slash_commands_enabled: false,
        structured_output: true,
        session_resume: false,
        known_limitations: []
      }
    end

    @impl true
    def run(_run_prompt, _workspace, _policy, _opts), do: {:error, :not_implemented}

    @impl true
    def cancel(_session_id), do: :ok
  end

  setup do
    project =
      Ash.create!(
        Project,
        %{name: "AgentRunner sample", local_path: "/tmp/agent-runner", default_branch: "main"},
        domain: Factory
      )

    plan =
      Ash.create!(
        Plan,
        %{
          project_id: project.id,
          title: "AgentRunner plan",
          intent: "Record adapter capabilities.",
          source_document: "docs/agent-runner.md",
          normalized_contract: %{"schema_version" => "conveyor.plan@1"},
          contract_sha256: digest("plan")
        },
        domain: Factory
      )

    epic =
      Ash.create!(Epic, %{plan_id: plan.id, title: "AgentRunner epic", description: "Adapter."},
        domain: Factory
      )

    slice =
      Ash.create!(Slice, %{epic_id: epic.id, title: "AgentRunner slice", position: 1},
        domain: Factory
      )

    %{slice: slice}
  end

  test "adapters without pre-exec policy are capped at L1 with negative capabilities" do
    snapshot =
      AgentRunner.agent_profile_snapshot(ObserveOnlyAdapter,
        adapter: "observe-only",
        model: "fake-observe"
      )

    assert snapshot["adapter"] == "observe-only"
    assert snapshot["model"] == "fake-observe"
    assert snapshot["autonomy_ceiling"] == "L1"
    refute snapshot["capabilities"]["pre_exec_command_policy"]
    assert "no_pre_exec_interception" in snapshot["known_limitations"]
    assert "adapter_reported_diff_only" in snapshot["known_limitations"]
    assert "unstructured_tool_calls" in snapshot["known_limitations"]
  end

  test "policy-controlled structured adapters can reach L2" do
    snapshot = AgentRunner.agent_profile_snapshot(PolicyControlledAdapter, adapter: "controlled")

    assert snapshot["autonomy_ceiling"] == "L2"
    assert snapshot["capabilities"]["pre_exec_command_policy"]
    assert snapshot["capabilities"]["diff_capture"] == "git_diff"
    refute "no_pre_exec_interception" in snapshot["known_limitations"]
  end

  test "capability snapshot is recorded in RunSpec", %{slice: slice} do
    snapshot = AgentRunner.agent_profile_snapshot(ObserveOnlyAdapter, adapter: "observe-only")
    run_spec = Ash.create!(RunSpec, run_spec_attrs(slice.id, snapshot), domain: Factory)

    assert run_spec.agent_profile_snapshot["adapter"] == "observe-only"
    assert run_spec.agent_profile_snapshot["autonomy_ceiling"] == "L1"
    assert "no_pre_exec_interception" in run_spec.agent_profile_snapshot["known_limitations"]
  end

  test "invalid capability declarations fail fast" do
    assert_raise ArgumentError, ~r/cancellation is invalid/, fn ->
      Capabilities.new!(%{cancellation: :eventually})
    end
  end

  defp run_spec_attrs(slice_id, agent_profile_snapshot) do
    run_spec_sha256 = digest("run-spec-agent-runner")

    %{
      slice_id: slice_id,
      attempt_no: 1,
      run_spec_json_ref: "artifacts/run-specs/agent-runner.json",
      run_spec_sha256: run_spec_sha256,
      base_commit: "abc123",
      contract_lock_sha256: digest("contract-lock"),
      prompt_template_version: "implementation-prompt@1",
      agent_profile_snapshot: agent_profile_snapshot,
      policy_sha256: digest("policy"),
      diff_policy_sha256: digest("diff-policy"),
      test_pack_sha256: digest("test-pack"),
      station_plan: station_plan(run_spec_sha256),
      station_plan_sha256: digest("station-plan"),
      container_image_ref: "ghcr.io/conveyor/sample-python-runner:2026-06-01",
      container_image_digest: digest("image"),
      sandbox_profile: "implement",
      budget_sha256: digest("budget"),
      code_quality_profile: "standard",
      canary_suite_version: "canary@1"
    }
  end

  defp station_plan(run_spec_sha256) do
    %{
      "schema_version" => "conveyor.station_plan@1",
      "stations" => [
        %{
          "key" => "implement",
          "kind" => "implementer",
          "input" => %{"run_spec_sha256" => run_spec_sha256},
          "output" => %{"run_spec_sha256" => run_spec_sha256}
        }
      ]
    }
  end

  defp digest(label), do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, label), case: :lower)
end
