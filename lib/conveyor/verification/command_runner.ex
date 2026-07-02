defmodule Conveyor.Verification.CommandRunner do
  @moduledoc """
  Generic locked-command runner (tt6v.1).

  Executes a single verification `command_spec` through the trusted `ToolExecutor` policy path
  (pre-exec allow/deny — the SOLE trusted execution seam) and returns the `{exit_code, stdout,
  stderr}` map `Evidence.VerificationRerunner` consumes. This replaces that module's no-op default
  runner so verification actually runs any-language command specs, not just pytest.

  Output handed to the format adapter is the command **stdout** by default, or — when the spec
  declares `result_artifact` (a workspace-relative file such as a junit XML path) — the contents
  of that file. Fail-honest: a policy-blocked command or a declared-but-missing artifact yields a
  non-zero result, never a silent pass. The low-level executor is injectable (`:exec`, default
  `Sandbox.Runner.exec/1`) so tests run a fixture command-spec matrix at $0.

  Environment preparation (python venv, elixir deps, js install) is profile business and stays out
  of this generic runner — it executes the already-resolved argv.
  """

  alias Conveyor.Config.CommandSpec
  alias Conveyor.Policy.NormalizedCommand
  alias Conveyor.Sandbox.Runner
  alias Conveyor.ToolExecutor

  # Convention: a command refused by policy exits 126 ("cannot execute") — deterministic failure,
  # not an infra error (which would trigger retries).
  @policy_blocked_exit 126

  @exec_opt_keys [
    :blob_root,
    :run_attempt_id,
    :agent_session_id,
    :station_run_id,
    :run_budget_id,
    # project/slice context so a policy-blocked command's violation record resolves its project.
    :project_id,
    :slice_id
  ]

  @doc """
  A runner `fn(command_spec_map)` bound to a workspace + policy, shaped for `VerificationRerunner`'s
  `:runner` seam.
  """
  @spec runner(String.t(), struct(), keyword()) :: (map() -> map())
  def runner(workspace_root, policy, opts \\ []) do
    fn command_spec -> run(command_spec, workspace_root, policy, opts) end
  end

  @doc "Execute one command spec; returns a map with exit_code, stdout and stderr keys."
  @spec run(map(), String.t(), struct(), keyword()) :: map()
  def run(command_spec, workspace_root, policy, opts \\ []) when is_map(command_spec) do
    normalized =
      command_spec
      |> to_command_spec()
      |> NormalizedCommand.normalize!(workspace_root: workspace_root)

    exec_opts =
      opts
      |> Keyword.take(@exec_opt_keys)
      |> Keyword.put(:runner, Keyword.get(opts, :exec, &Runner.exec/1))

    result = ToolExecutor.execute!(normalized, policy, exec_opts)

    case result.decision.status do
      :blocked ->
        %{
          "exit_code" => @policy_blocked_exit,
          "stdout" => "",
          "stderr" => "policy blocked: #{result.decision.message}"
        }

      :allowed ->
        collect_output(result.execution, command_spec, workspace_root)
    end
  end

  defp collect_output(%Runner.Result{} = execution, command_spec, workspace_root) do
    case declared_artifact(command_spec) do
      nil ->
        %{
          "exit_code" => execution.exit_code,
          "stdout" => execution.stdout,
          "stderr" => execution.stderr
        }

      rel_path ->
        read_artifact(rel_path, execution, workspace_root)
    end
  end

  defp read_artifact(rel_path, execution, workspace_root) do
    path = Path.join(Path.expand(workspace_root), rel_path)

    case File.read(path) do
      {:ok, contents} ->
        %{"exit_code" => execution.exit_code, "stdout" => contents, "stderr" => execution.stderr}

      {:error, reason} ->
        %{
          "exit_code" => nonzero(execution.exit_code),
          "stdout" => "",
          "stderr" => "missing result artifact #{rel_path}: #{:file.format_error(reason)}"
        }
    end
  end

  # A missing artifact must fail even when the command itself exited 0 (fail-honest).
  defp nonzero(0), do: 1
  defp nonzero(code), do: code

  defp declared_artifact(command_spec), do: value(command_spec, "result_artifact")

  defp to_command_spec(map) do
    argv = value(map, "argv", [])

    %CommandSpec{
      key: value(map, "key", List.first(argv)),
      argv: argv,
      cwd: value(map, "cwd", "."),
      profile: to_atom(value(map, "profile", "verify")),
      required: value(map, "required", true),
      timeout_ms: value(map, "timeout_ms", 120_000),
      network: to_atom(value(map, "network", "none")),
      env_allowlist: value(map, "env_allowlist", []),
      output_limit_bytes: value(map, "output_limit_bytes", 2_000_000),
      result_format: to_atom(value(map, "result_format", "stdout")),
      result_adapter: value(map, "result_adapter")
    }
  end

  defp to_atom(value) when is_atom(value), do: value
  defp to_atom(value) when is_binary(value), do: String.to_existing_atom(value)

  defp value(map, key, default \\ nil) when is_map(map) do
    case Map.get(map, key, Map.get(map, safe_atom(key))) do
      nil -> default
      found -> found
    end
  end

  defp safe_atom(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> :"#{key}__absent"
  end
end
