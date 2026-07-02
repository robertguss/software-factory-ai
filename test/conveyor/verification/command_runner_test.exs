defmodule Conveyor.Verification.CommandRunnerTest do
  @moduledoc "tt6v.1: generic locked-command runner over the trusted ToolExecutor policy path."
  use Conveyor.DataCase, async: false

  alias Conveyor.Factory.Policy
  alias Conveyor.Sandbox.Runner
  alias Conveyor.Verification.CommandRunner

  setup do
    %{ws: tmp!("cmdrunner-ws"), blob: tmp!("cmdrunner-blob")}
  end

  test "stdout format passes the command stdout and exit code through", %{ws: ws, blob: blob} do
    result =
      CommandRunner.run(spec(["echo", "hi"]), ws, policy(),
        exec: ok_exec("hi\n"),
        blob_root: blob
      )

    assert result["exit_code"] == 0
    assert result["stdout"] == "hi\n"
  end

  test "a nonzero exit code is propagated (fail honest)", %{ws: ws, blob: blob} do
    result =
      CommandRunner.run(spec(["echo", "x"]), ws, policy(),
        exec: ok_exec("boom", 2),
        blob_root: blob
      )

    assert result["exit_code"] == 2
  end

  test "json format hands stdout to the caller for the json adapter", %{ws: ws, blob: blob} do
    json = ~s({"tests":[]})
    spec = spec(["echo", "x"], %{"result_format" => "json"})
    result = CommandRunner.run(spec, ws, policy(), exec: ok_exec(json), blob_root: blob)

    assert result["stdout"] == json
  end

  test "junit via a declared result_artifact reads the file, not stdout", %{ws: ws, blob: blob} do
    junit_rel = "out/junit.xml"
    xml = "<testsuite name=\"x\"/>"

    exec = fn _command ->
      File.mkdir_p!(Path.join(ws, "out"))
      File.write!(Path.join(ws, junit_rel), xml)
      %Runner.Result{exit_code: 0, stdout: "console noise", stderr: "", duration_ms: 1}
    end

    spec = spec(["echo", "x"], %{"result_format" => "junit", "result_artifact" => junit_rel})
    result = CommandRunner.run(spec, ws, policy(), exec: exec, blob_root: blob)

    assert result["stdout"] == xml
    refute result["stdout"] =~ "console noise"
  end

  test "a declared-but-missing artifact fails honest even on exit 0", %{ws: ws, blob: blob} do
    spec = spec(["echo", "x"], %{"result_format" => "junit", "result_artifact" => "nope.xml"})
    result = CommandRunner.run(spec, ws, policy(), exec: ok_exec("", 0), blob_root: blob)

    assert result["exit_code"] != 0
    assert result["stderr"] =~ "missing result artifact"
  end

  test "policy pre-exec check refuses a disallowed command and never executes it", %{
    ws: ws,
    blob: blob
  } do
    parent = self()

    exec = fn _command ->
      send(parent, :ran)
      ok_result()
    end

    project =
      Ash.create!(
        Conveyor.Factory.Project,
        %{name: "cmdrunner", local_path: ws, default_branch: "main", default_autonomy_level: 1},
        domain: Conveyor.Factory
      )

    result =
      CommandRunner.run(spec(["curl", "http://evil"]), ws, policy(allowlist: ["echo"]),
        exec: exec,
        blob_root: blob,
        project_id: project.id
      )

    refute_received :ran
    assert result["exit_code"] == 126
    assert result["stderr"] =~ "policy blocked"
  end

  test "runner/3 returns a fn shaped for VerificationRerunner's :runner seam", %{
    ws: ws,
    blob: blob
  } do
    run = CommandRunner.runner(ws, policy(), exec: ok_exec("ok\n"), blob_root: blob)
    result = run.(spec(["echo", "ok"]))

    assert result["exit_code"] == 0
    assert result["stdout"] == "ok\n"
  end

  defp spec(argv, extra \\ %{}) do
    Map.merge(
      %{
        "key" => List.first(argv),
        "argv" => argv,
        "cwd" => ".",
        "profile" => "verify",
        "network" => "none",
        "env_allowlist" => [],
        "timeout_ms" => 120_000,
        "result_format" => "stdout"
      },
      extra
    )
  end

  defp policy(opts \\ []) do
    %Policy{
      name: "verify",
      profile: :verify,
      allowlist: Keyword.get(opts, :allowlist, ["echo"]),
      denylist: Keyword.get(opts, :denylist, []),
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

  defp ok_result, do: %Runner.Result{exit_code: 0, stdout: "", stderr: "", duration_ms: 1}

  defp tmp!(prefix) do
    path = Path.join(System.tmp_dir!(), "#{prefix}-#{System.unique_integer([:positive])}")
    File.mkdir_p!(path)
    on_exit(fn -> File.rm_rf!(path) end)
    path
  end
end
