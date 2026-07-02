defmodule Conveyor.Verification.CommandSuiteRunnerTest do
  @moduledoc "tt6v.1: generic verification_result producer + verify-station dispatch through the seam."
  use Conveyor.DataCase, async: false

  alias Conveyor.Factory.Policy
  alias Conveyor.Sandbox.Runner
  alias Conveyor.Stations.Verify
  alias Conveyor.Verification.CommandSuiteRunner

  setup do
    %{ws: tmp!("suite-ws"), blob: tmp!("suite-blob")}
  end

  test "runs the locked command_specs and builds a passing acceptance_locked suite", %{
    ws: ws,
    blob: blob
  } do
    result =
      CommandSuiteRunner.verification_result([cmd(["echo", "ok"])], ws, policy(),
        exec: ok_exec("ok\n"),
        blob_root: blob
      )

    assert result["status"] == "passed"
    assert [suite] = result["suites"]
    assert suite["suite_kind"] == "acceptance_locked"
    assert String.starts_with?(result["result_digest"], "sha256:")
    assert [command] = suite["commands"]
    assert command["argv"] == ["echo", "ok"]
  end

  test "a nonzero command fails the suite (fail honest)", %{ws: ws, blob: blob} do
    result =
      CommandSuiteRunner.verification_result([cmd(["echo", "x"])], ws, policy(),
        exec: ok_exec("boom", 2),
        blob_root: blob
      )

    assert result["status"] == "failed"
  end

  test "an empty command set cannot pass (dr1m.7)", %{ws: ws, blob: blob} do
    result = CommandSuiteRunner.verification_result([], ws, policy(), blob_root: blob)
    assert result["status"] == "failed"
  end

  test "verify station dispatches to the generic seam on verification_engine=command (tt6v.1)", %{
    ws: ws,
    blob: blob
  } do
    input = %{
      "workspace_path" => ws,
      "blob_root" => blob,
      "verification_engine" => "command",
      "policy" => policy(),
      "exec" => ok_exec("ok\n"),
      "plan" => %{"verification_commands" => [cmd(["echo", "ok"])]}
    }

    assert {:ok, output} = Verify.run(input, %{})

    verification_result = output["verification_result"]
    assert verification_result["status"] == "passed"
    assert output["verification_status"] == "passed"
    assert [%{"suite_kind" => "acceptance_locked"}] = verification_result["suites"]
    # the station still produces its integrity verdict over the generic result
    assert output["integrity_verdict"]
  end

  defp cmd(argv) do
    %{
      "key" => Enum.join(argv, "-"),
      "argv" => argv,
      "cwd" => ".",
      "profile" => "verify",
      "network" => "none",
      "env_allowlist" => [],
      "timeout_ms" => 120_000,
      "result_format" => "stdout"
    }
  end

  defp policy(opts \\ []) do
    %Policy{
      name: "verify",
      profile: :verify,
      allowlist: Keyword.get(opts, :allowlist, ["echo"]),
      denylist: [],
      env_policy: %{"allowlist" => []},
      network_policy: %{"default" => "none"},
      budget_policy: %{},
      autonomy_ceiling: 1
    }
  end

  defp ok_exec(stdout, exit_code \\ 0) do
    fn _command ->
      %Runner.Result{exit_code: exit_code, stdout: stdout, stderr: "", duration_ms: 1}
    end
  end

  defp tmp!(prefix) do
    path = Path.join(System.tmp_dir!(), "#{prefix}-#{System.unique_integer([:positive])}")
    File.mkdir_p!(path)
    on_exit(fn -> File.rm_rf!(path) end)
    path
  end
end
