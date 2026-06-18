defmodule Conveyor.Policy.EvalFixturesTest do
  use Conveyor.DataCase, async: false

  import Conveyor.FactoryFixtures

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

  @fixtures_path "test/fixtures/policy_eval/dangerous_commands.json"

  test "policy eval fixtures are blocked and recorded with incidents" do
    fixtures = load_fixtures!()
    context = run_context!("all")

    Enum.each(fixtures, fn fixture ->
      command = normalized_command(fixture, context.workspace_root)
      policy = policy(fixture)
      parent = self()

      result =
        ToolExecutor.execute!(command, policy,
          blob_root: context.blob_root,
          run_attempt_id: context.run_attempt.id,
          station_run_id: context.station_run.id,
          runner: fn _command ->
            send(parent, {:runner_called, fixture["label"]})
            %Runner.Result{exit_code: 0, stdout: "should not run", stderr: "", duration_ms: 1}
          end
        )

      refute_received {:runner_called, _label}
      assert result.decision.status == :blocked
      assert Atom.to_string(result.decision.reason) == fixture["expected_reason"]
      assert result.invocation.status == :blocked
      assert result.invocation.policy_decision == :blocked

      assert [%ToolInvocation{}] =
               ToolInvocation
               |> Ash.read!(domain: Factory)
               |> Enum.filter(&(&1.id == result.invocation.id))

      assert %Incident{} = result.violation.incident
      assert result.violation.incident.category == "policy_violation"

      assert result.violation.incident.evidence_refs == [
               "tool-invocations/#{result.invocation.id}"
             ]

      assert get_by_id!(RunAttempt, context.run_attempt.id).status == :failed
      assert get_by_id!(Slice, context.slice.id).state == :policy_blocked

      assert [_event] =
               LedgerEvent
               |> Ash.read!(domain: Factory)
               |> Enum.filter(&(&1.payload["tool_invocation_id"] == result.invocation.id))
    end)
  end

  defp load_fixtures! do
    @fixtures_path
    |> File.read!()
    |> Jason.decode!()
  end

  defp run_context!(label) do
    blob_root = temp_dir!("policy-eval-blobs-#{label}")
    workspace_root = temp_dir!("policy-eval-workspace-#{label}")

    fixture =
      create_artifact_run!(
        blob_root: blob_root,
        artifact_content: "policy eval #{label}\n",
        local_path: Path.join(System.tmp_dir!(), "policy-eval-project-#{label}"),
        project_name: "Policy eval #{label}"
      )

    slice =
      fixture.run_attempt.slice_id
      |> then(&get_by_id!(Slice, &1))
      |> Ash.update!(%{state: :in_progress}, domain: Factory)

    run_attempt = Ash.update!(fixture.run_attempt, %{status: :running}, domain: Factory)

    %{
      blob_root: blob_root,
      run_attempt: run_attempt,
      slice: slice,
      station_run: fixture.station_run,
      workspace_root: workspace_root
    }
  end

  defp normalized_command(fixture, workspace_root) do
    command_spec = %CommandSpec{
      key: List.first(fixture["argv"]),
      argv: fixture["argv"],
      profile: :verify,
      network: network(fixture),
      env_allowlist: Map.get(fixture, "env_allowlist", []),
      timeout_ms: 120_000
    }

    NormalizedCommand.normalize!(command_spec, workspace_root: workspace_root)
  end

  defp policy(fixture) do
    %Policy{
      name: "policy-eval",
      profile: :verify,
      allowlist: fixture["allowlist"],
      denylist: fixture["denylist"],
      env_policy: %{"allowlist" => ["MIX_ENV", "PYTHONPATH"]},
      network_policy: %{"default" => "none"},
      budget_policy: %{},
      autonomy_ceiling: 1
    }
  end

  defp network(%{"network" => "egress"}), do: :egress
  defp network(%{"network" => "loopback"}), do: :loopback
  defp network(_fixture), do: :none

  defp get_by_id!(resource, id) do
    resource
    |> Ash.read!(domain: Factory)
    |> Enum.find(&(&1.id == id))
  end
end
