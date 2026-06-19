defmodule Mix.Tasks.ConveyorPlanLintTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  test "plan_lint emits SARIF with source anchors and exits two when blocked" do
    path = write_json!(problem_contract())
    put_exit_fun(:conveyor_plan_lint_exit_fun)

    output =
      capture_io(fn ->
        Mix.Task.reenable("conveyor.plan_lint")
        Mix.Task.run("conveyor.plan_lint", [path, "--format", "sarif"])
      end)

    sarif = Jason.decode!(output)

    assert sarif["version"] == "2.1.0"
    assert [%{"tool" => %{"driver" => %{"name" => "conveyor.plan_lint"}}}] = sarif["runs"]

    assert output =~ "missing_hard_constraint"
    assert output =~ "plan.md#ac-1"
    assert_received {:exit_code, 2}
  after
    Process.delete(:conveyor_plan_lint_exit_fun)
  end

  test "contract_lint emits canonical JSON without execution authority" do
    path = write_json!(problem_contract())
    put_exit_fun(:conveyor_contract_lint_exit_fun)

    output =
      capture_io(fn ->
        Mix.Task.reenable("conveyor.contract_lint")
        Mix.Task.run("conveyor.contract_lint", [path, "--format", "json"])
      end)

    report = Jason.decode!(output)

    assert report["schema_version"] == "conveyor.plan_lint@1"
    assert report["status"] == "blocked"
    assert report["authority_effect"] == "none"
    assert report["creates_ready_slice?"] == false
    assert Enum.any?(report["findings"], &(&1["rule_key"] == "weak_oracle_path"))
    assert_received {:exit_code, 2}
  after
    Process.delete(:conveyor_contract_lint_exit_fun)
  end

  test "plan_prepare --no-agents produces a static non-authorizing package" do
    path = write_json!(clean_contract())
    put_exit_fun(:conveyor_plan_prepare_exit_fun)

    output =
      capture_io(fn ->
        Mix.Task.reenable("conveyor.plan_prepare")
        Mix.Task.run("conveyor.plan_prepare", [path, "--no-agents", "--format", "json"])
      end)

    report = Jason.decode!(output)

    assert report["schema_version"] == "conveyor.plan_prepare@1"
    assert report["status"] == "passed"
    assert report["no_agents"] == true
    assert report["agent_runner_used"] == false
    assert report["provider_credentials_required"] == false
    assert report["authority_effect"] == "none"
    assert report["creates_contract_lock?"] == false
    assert_received {:exit_code, 0}
  after
    Process.delete(:conveyor_plan_prepare_exit_fun)
  end

  defp put_exit_fun(key) do
    test_pid = self()
    Process.put(key, fn code -> send(test_pid, {:exit_code, code}) end)
  end

  defp write_json!(payload) do
    path =
      Path.join(
        System.tmp_dir!(),
        "conveyor-plan-lint-#{System.unique_integer([:positive])}.json"
      )

    File.write!(path, Jason.encode!(payload))
    path
  end

  defp problem_contract do
    %{
      "requirements" => [
        %{"key" => "REQ-001", "text" => "Tasks must be listed.", "source_ref" => "plan.md#req-1"}
      ],
      "acceptance_criteria" => [
        %{
          "key" => "AC-001",
          "text" => "Tasks are better and robust.",
          "requirement_refs" => ["REQ-001"],
          "oracle_refs" => ["manual_check"],
          "source_ref" => "plan.md#ac-1"
        }
      ],
      "non_goals" => ["Authentication"],
      "decisions" => [
        %{"key" => "DEC-001", "decision" => "Choose storage.", "status" => "unresolved"}
      ],
      "interfaces" => [%{"key" => "TasksAPI", "version" => "v1", "required_by" => ["SLICE-001"]}],
      "context_budget" => %{"critical_required_tokens" => 12_000, "max_tokens" => 8_000}
    }
  end

  defp clean_contract do
    %{
      "requirements" => [
        %{"key" => "REQ-001", "text" => "Tasks must be listed.", "source_ref" => "plan.md#req-1"}
      ],
      "acceptance_criteria" => [
        %{
          "key" => "AC-001",
          "text" => "List responses include created tasks.",
          "requirement_refs" => ["REQ-001"],
          "required_test_refs" => ["test/tasks_test.exs::list"],
          "source_ref" => "plan.md#ac-1"
        }
      ],
      "non_goals" => ["Authentication"],
      "decisions" => [%{"key" => "DEC-001", "decision" => "Keep auth out of scope."}],
      "constraints" => [%{"key" => "CON-001", "strength" => "hard", "statement" => "No auth."}],
      "interfaces" => [
        %{"key" => "TasksAPI", "version" => "v1", "schema_ref" => "schema://tasks-v1"}
      ],
      "context_budget" => %{"critical_required_tokens" => 1_000, "max_tokens" => 8_000}
    }
  end
end
