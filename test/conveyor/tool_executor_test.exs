defmodule Conveyor.ToolExecutorTest do
  use Conveyor.DataCase, async: false

  import Conveyor.FactoryFixtures

  alias Conveyor.Artifacts.BlobStore
  alias Conveyor.Config.CommandSpec
  alias Conveyor.Factory
  alias Conveyor.Factory.Incident
  alias Conveyor.Factory.LedgerEvent
  alias Conveyor.Factory.Policy
  alias Conveyor.Factory.RunAttempt
  alias Conveyor.Factory.Slice
  alias Conveyor.Factory.ToolInvocation
  alias Conveyor.Policy.NormalizedCommand
  alias Conveyor.Sandbox.Runner
  alias Conveyor.ToolExecutor

  setup do
    blob_root = temp_dir!("tool-executor-blobs")

    fixture =
      create_artifact_run!(
        blob_root: blob_root,
        artifact_content: "tool executor fixture\n"
      )

    slice = get_by_id!(Slice, fixture.run_attempt.slice_id)

    %{
      blob_root: blob_root,
      project: fixture.project,
      run_attempt: fixture.run_attempt,
      slice: slice,
      station_run: fixture.station_run
    }
  end

  test "records a blocked invocation without executing the runner", %{
    blob_root: blob_root,
    run_attempt: run_attempt,
    station_run: station_run
  } do
    parent = self()
    command = normalized_command(["bash", "-lc", "mix test"])
    policy = policy(allowlist: ["mix"])

    result =
      ToolExecutor.execute!(command, policy,
        blob_root: blob_root,
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
    assert invocation.duration_ms >= 0
    assert invocation.output_sha256 == digest("")
    assert blob_content!(blob_root, invocation.stdout_ref) == ""
    assert blob_content!(blob_root, invocation.stderr_ref) == ""
  end

  test "evaluates policy before executing and records a trusted successful invocation", %{
    blob_root: blob_root,
    run_attempt: run_attempt,
    station_run: station_run
  } do
    parent = self()
    command = normalized_command(["echo", "ok"], env_allowlist: ["MIX_ENV"])
    policy = policy(allowlist: ["echo"], env_policy: %{"allowlist" => ["MIX_ENV"]})

    result =
      ToolExecutor.execute!(command, policy,
        blob_root: blob_root,
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
    assert blob_content!(blob_root, result.invocation.stdout_ref) == "ok\n"
    assert blob_content!(blob_root, result.invocation.stderr_ref) == ""
    assert ToolExecutor.trusted_invocation?(result.invocation)
  end

  test "records failed executions as failed but still policy-allowed", %{
    blob_root: blob_root,
    run_attempt: run_attempt,
    station_run: station_run
  } do
    command = normalized_command(["mix", "test"])
    policy = policy(allowlist: ["mix"])

    result =
      ToolExecutor.execute!(command, policy,
        blob_root: blob_root,
        run_attempt_id: run_attempt.id,
        station_run_id: station_run.id,
        runner: fn _command ->
          %Runner.Result{exit_code: 2, stdout: "failure\n", stderr: "", duration_ms: 15}
        end
      )

    assert result.invocation.status == :failed
    assert result.invocation.policy_decision == :allowed
    assert result.invocation.exit_code == 2
    assert blob_content!(blob_root, result.invocation.stdout_ref) == "failure\n"
    assert blob_content!(blob_root, result.invocation.stderr_ref) == ""
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

  test "blocked policy violations create an incident, stop the run, and transition the slice", %{
    blob_root: blob_root,
    run_attempt: run_attempt,
    slice: slice,
    station_run: station_run
  } do
    slice = Ash.update!(slice, %{state: :in_progress}, domain: Factory)
    run_attempt = Ash.update!(run_attempt, %{status: :running}, domain: Factory)

    command = normalized_command(["git", "reset", "--hard", "HEAD"])
    policy = policy(allowlist: ["git"], denylist: ["git reset --hard"])

    result =
      ToolExecutor.execute!(command, policy,
        blob_root: blob_root,
        run_attempt_id: run_attempt.id,
        station_run_id: station_run.id,
        runner: fn _command -> flunk("blocked commands must not execute") end
      )

    assert result.decision.reason == :denylisted
    assert result.invocation.status == :blocked

    assert [incident] = Ash.read!(Incident, domain: Factory)
    assert incident.category == "policy_violation"
    assert incident.severity == :error
    assert incident.run_attempt_id == run_attempt.id
    assert incident.slice_id == slice.id
    assert incident.evidence_refs == ["tool-invocations/#{result.invocation.id}"]

    stopped_attempt = get_by_id!(RunAttempt, run_attempt.id)
    assert stopped_attempt.status == :failed
    assert stopped_attempt.outcome == :policy_blocked
    assert stopped_attempt.failure_category == "policy_violation"

    blocked_slice = get_by_id!(Slice, slice.id)
    assert blocked_slice.state == :policy_blocked

    assert [event] =
             LedgerEvent
             |> Ash.read!(domain: Factory)
             |> Enum.filter(&(&1.type == "policy.blocked"))

    assert event.run_attempt_id == run_attempt.id
    assert event.payload["incident_id"] == incident.id
    assert event.payload["tool_invocation_id"] == result.invocation.id
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

  defp blob_content!(blob_root, blob_ref) do
    BlobStore.read!(blob_ref, blob_root: blob_root)
  end

  defp get_by_id!(resource, id) do
    resource
    |> Ash.read!(domain: Factory)
    |> Enum.find(&(&1.id == id))
  end
end
