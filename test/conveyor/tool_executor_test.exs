defmodule Conveyor.ToolExecutorTest do
  use Conveyor.DataCase, async: false

  import Conveyor.FactoryFixtures

  alias Conveyor.Config.CommandSpec
  alias Conveyor.Factory
  alias Conveyor.Factory.Policy
  alias Conveyor.Factory.ToolInvocation
  alias Conveyor.Policy.NormalizedCommand
  alias Conveyor.Sandbox.Runner
  alias Conveyor.ToolExecutor

  setup do
    fixture =
      create_artifact_run!(
        blob_root: temp_dir!("tool-executor-blobs"),
        artifact_content: "tool executor fixture\n"
      )

    %{run_attempt: fixture.run_attempt, station_run: fixture.station_run}
  end

  test "records a blocked invocation without executing the runner", %{
    run_attempt: run_attempt,
    station_run: station_run
  } do
    parent = self()
    command = normalized_command(["bash", "-lc", "mix test"])
    policy = policy(allowlist: ["mix"])

    result =
      ToolExecutor.execute!(command, policy,
        run_attempt_id: run_attempt.id,
        station_run_id: station_run.id,
        runner: fn _command ->
          send(parent, :runner_called)
          successful_result()
        end
      )

    refute_received :runner_called
    assert result.decision.status == :blocked
    assert result.invocation.status == :blocked
    assert result.invocation.policy_decision == :blocked
    assert result.execution == nil

    assert [invocation] = Ash.read!(ToolInvocation, domain: Factory)
    assert invocation.id == result.invocation.id
    assert invocation.invocation_kind == "tool_executor"
    assert invocation.command_spec["argv"] == ["bash", "-lc", "mix test"]
    assert invocation.exit_code == nil
  end

  test "evaluates policy before executing and records a trusted successful invocation", %{
    run_attempt: run_attempt,
    station_run: station_run
  } do
    parent = self()
    command = normalized_command(["echo", "ok"], env_allowlist: ["MIX_ENV"])
    policy = policy(allowlist: ["echo"], env_policy: %{"allowlist" => ["MIX_ENV"]})

    result =
      ToolExecutor.execute!(command, policy,
        run_attempt_id: run_attempt.id,
        station_run_id: station_run.id,
        runner: fn executed_command ->
          send(parent, {:runner_called, executed_command})
          successful_result()
        end
      )

    assert_received {:runner_called, ^command}
    assert result.decision.status == :allowed
    assert result.invocation.status == :succeeded
    assert result.invocation.policy_decision == :allowed
    assert result.invocation.exit_code == 0
    assert result.invocation.output_sha256 == digest("ok\n")
    assert ToolExecutor.trusted_invocation?(result.invocation)
  end

  test "records failed executions as failed but still policy-allowed", %{
    run_attempt: run_attempt,
    station_run: station_run
  } do
    command = normalized_command(["mix", "test"])
    policy = policy(allowlist: ["mix"])

    result =
      ToolExecutor.execute!(command, policy,
        run_attempt_id: run_attempt.id,
        station_run_id: station_run.id,
        runner: fn _command ->
          %Runner.Result{exit_code: 2, stdout: "failure\n", stderr: "", duration_ms: 15}
        end
      )

    assert result.invocation.status == :failed
    assert result.invocation.policy_decision == :allowed
    assert result.invocation.exit_code == 2
  end

  test "adapter-reported invocations are not trusted command executions" do
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

  defp normalized_command(argv, opts \\ []) do
    workspace_root = temp_dir!("tool-executor-workspace")

    command_spec = %CommandSpec{
      key: List.first(argv),
      argv: argv,
      profile: :verify,
      network: Keyword.get(opts, :network, :none),
      env_allowlist: Keyword.get(opts, :env_allowlist, []),
      timeout_ms: 120_000
    }

    NormalizedCommand.normalize!(command_spec, workspace_root: workspace_root)
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

  defp successful_result do
    %Runner.Result{exit_code: 0, stdout: "ok\n", stderr: "", duration_ms: 5}
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
      "result_format" => "stdout"
    }
  end

  defp digest(content), do: Base.encode16(:crypto.hash(:sha256, content), case: :lower)
end
