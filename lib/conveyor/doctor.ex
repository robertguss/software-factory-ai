defmodule Conveyor.Doctor do
  @moduledoc "Operator prerequisite checks for Conveyor projects."

  alias Conveyor.CLI.ExitCodes
  alias Conveyor.CLI.NextAction
  alias Conveyor.Config
  alias Conveyor.Config.ProjectConfig
  alias Conveyor.Doctor.Finding
  alias Conveyor.Doctor.Result

  @type executable_fun :: (String.t() -> boolean())
  @type postgres_fun :: (keyword() -> :ok | {:error, term()})
  @type git_fun :: (String.t(), [String.t()], keyword() -> {String.t(), non_neg_integer()})

  @spec run(Path.t(), keyword()) :: Result.t()
  def run(project_path \\ File.cwd!(), opts \\ []) do
    project_path = Path.expand(project_path)
    executable? = Keyword.get(opts, :executable?, &default_executable?/1)
    postgres_check = Keyword.get(opts, :postgres_check, &default_postgres_check/1)
    git_command = Keyword.get(opts, :git_command, &System.cmd/3)

    {config, findings} = load_config(project_path)

    findings =
      findings
      |> Kernel.++(check_versions())
      |> Kernel.++(check_oban())
      |> Kernel.++(check_postgres(postgres_check))
      |> Kernel.++(check_docker(executable?))
      |> Kernel.++(check_git(project_path, executable?))
      |> Kernel.++(check_sample_repo(project_path, config, executable?, git_command))
      |> Kernel.++(check_project_files(project_path, config))
      |> Kernel.++(check_optional_adapters(config, executable?))
      |> Kernel.++(check_secret_posture())

    %Result{
      status: status(findings),
      findings: findings,
      host_capabilities: %{docker: executable?.("docker"), git: executable?.("git")}
    }
  end

  @spec format(Result.t()) :: String.t()
  def format(%Result{} = result) do
    header = "Conveyor doctor: #{result.status}"

    body =
      result.findings
      |> Enum.flat_map(&format_finding/1)

    Enum.join([header | body], "\n")
  end

  @spec exit_code(Result.t()) :: non_neg_integer()
  def exit_code(%Result{status: :passed}), do: ExitCodes.fetch!(:success)

  def exit_code(%Result{findings: findings}) do
    cond do
      Enum.any?(findings, &(&1.check in [:config])) ->
        ExitCodes.fetch!(:malformed_artifact_or_schema_failure)

      Enum.any?(findings, &(&1.check in [:policy_profiles, :secret_posture])) ->
        ExitCodes.fetch!(:policy_or_secret_safety_violation)

      true ->
        ExitCodes.fetch!(:infrastructure_or_doctor_failure)
    end
  end

  defp load_config(project_path) do
    config_path = Config.default_path(project_path)

    case Config.load(config_path) do
      {:ok, config} -> {config, []}
      {:error, error} -> {nil, [failure(:config, error.message, "Fix .conveyor/config.toml")]}
    end
  end

  defp check_versions do
    versions = Conveyor.ToolMatrix.latest_tested_versions()

    [
      version_check(:elixir_version, System.version(), versions.elixir),
      otp_check(versions.otp),
      version_check(
        :phoenix_version,
        Conveyor.RuntimeVersions.app_version(:phoenix),
        versions.phoenix
      ),
      version_check(:ash_version, Conveyor.RuntimeVersions.app_version(:ash), versions.ash),
      version_check(:oban_version, Conveyor.RuntimeVersions.app_version(:oban), versions.oban)
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp version_check(check, actual, requirement) do
    if Version.match?(Version.parse!(actual), requirement) do
      nil
    else
      failure(
        check,
        "#{actual} does not match tested matrix #{requirement}",
        "Install the tested runtime"
      )
    end
  end

  defp otp_check(">= " <> minimum) do
    actual =
      :erlang.system_info(:otp_release)
      |> to_string()
      |> String.to_integer()

    if actual >= String.to_integer(minimum) do
      nil
    else
      failure(
        :otp_version,
        "OTP #{actual} does not match tested matrix >= #{minimum}",
        "Install the tested OTP runtime"
      )
    end
  end

  defp check_oban do
    oban_config = Application.get_env(:conveyor, Oban, [])

    if Keyword.get(oban_config, :repo) == Conveyor.Repo do
      []
    else
      [failure(:oban, "Oban is not configured with Conveyor.Repo", "Fix Oban application config")]
    end
  end

  defp check_postgres(postgres_check) do
    case postgres_check.(Conveyor.Repo.config()) do
      :ok ->
        []

      {:error, reason} ->
        [
          failure(
            :postgres,
            "Postgres is not reachable: #{inspect(reason)}",
            "Start Postgres and verify database env vars"
          )
        ]
    end
  end

  defp default_postgres_check(repo_config) do
    opts =
      repo_config
      |> Keyword.take([:hostname, :port, :username, :password, :database])
      |> Keyword.put_new(:timeout, 1_000)

    case Postgrex.start_link(opts) do
      {:ok, pid} ->
        GenServer.stop(pid)
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp check_docker(executable?) do
    if executable?.("docker") do
      []
    else
      [failure(:docker, "Docker is not reachable or not installed", "Install or start Docker")]
    end
  end

  defp check_git(project_path, executable?) do
    cond do
      not executable?.("git") ->
        [failure(:git, "git is not installed", "Install git")]

      not File.dir?(Path.join(project_path, ".git")) ->
        [warning(:git, "project path is not a git repository")]

      true ->
        []
    end
  end

  defp check_sample_repo(_project_path, nil, _executable?, _git_command), do: []

  defp check_sample_repo(
         project_path,
         %ProjectConfig{sample_repo_path: sample_repo_path, sample_base_ref: sample_base_ref},
         executable?,
         git_command
       ) do
    cond do
      is_nil(sample_repo_path) and is_nil(sample_base_ref) ->
        []

      is_nil(sample_repo_path) or is_nil(sample_base_ref) ->
        [
          failure(
            :sample_repo,
            "sample_repo_path and sample_base_ref must be configured together",
            "Set both keys in .conveyor/config.toml"
          )
        ]

      not executable?.("git") ->
        []

      true ->
        sample_repo_path
        |> Path.expand(project_path)
        |> check_sample_repo_path(sample_base_ref, git_command)
    end
  end

  defp check_sample_repo_path(sample_path, sample_base_ref, git_command) do
    cond do
      not File.dir?(sample_path) ->
        [
          failure(
            :sample_repo,
            "sample repo path does not exist: #{sample_path}",
            "Create the sample repo or update sample_repo_path"
          )
        ]

      not git_success?(git_command, sample_path, ["rev-parse", "--is-inside-work-tree"]) ->
        [
          failure(
            :sample_repo,
            "sample repo path is not inside a git working tree: #{sample_path}",
            "Initialize or materialize the sample repo from the expected base commit"
          )
        ]

      not git_success?(git_command, sample_path, [
        "rev-parse",
        "--verify",
        "#{sample_base_ref}^{commit}"
      ]) ->
        [
          failure(
            :sample_repo,
            "sample base ref cannot be resolved: #{sample_base_ref}",
            "Record a valid sample_base_ref in .conveyor/config.toml"
          )
        ]

      (status =
         git_output(git_command, git_root(git_command, sample_path), [
           "status",
           "--porcelain",
           "--",
           git_pathspec(git_command, sample_path)
         ])) != "" ->
        [
          failure(
            :sample_repo,
            "sample repo has uncommitted changes: #{summarize_git_status(status)}",
            "Restore or commit sample repo changes before running Conveyor"
          )
        ]

      not git_success?(
        git_command,
        git_root(git_command, sample_path),
        ["diff", "--quiet", sample_base_ref, "--", git_pathspec(git_command, sample_path)]
      ) ->
        [
          failure(
            :sample_repo,
            "sample repo tree differs from expected base ref #{sample_base_ref}",
            "Reset or materialize the sample repo at the recorded base commit"
          )
        ]

      true ->
        []
    end
  end

  defp git_success?(git_command, cwd, args) do
    {_output, status} = git_command.("git", ["-C", cwd | args], stderr_to_stdout: true)
    status == 0
  end

  defp git_output(git_command, cwd, args) do
    {output, 0} = git_command.("git", ["-C", cwd | args], stderr_to_stdout: true)
    String.trim(output)
  end

  defp git_root(git_command, cwd) do
    git_output(git_command, cwd, ["rev-parse", "--show-toplevel"])
  end

  defp git_pathspec(git_command, cwd) do
    case git_output(git_command, cwd, ["rev-parse", "--show-prefix"]) do
      "" -> "."
      prefix -> String.trim_trailing(prefix, "/")
    end
  end

  defp summarize_git_status(status) do
    status
    |> String.split("\n", trim: true)
    |> Enum.take(3)
    |> Enum.join("; ")
  end

  defp check_project_files(project_path, %ProjectConfig{} = config) do
    []
    |> Kernel.++(check_agents(project_path))
    |> Kernel.++(check_command_specs(config))
    |> Kernel.++(check_policy_files(project_path, config))
    |> Kernel.++(check_artifact_dirs(project_path, config))
  end

  defp check_project_files(_project_path, nil), do: []

  defp check_agents(project_path) do
    if File.regular?(Path.join(project_path, "AGENTS.md")) do
      []
    else
      [failure(:agents_md, "AGENTS.md is missing", "Run mix conveyor.init")]
    end
  end

  defp check_command_specs(%ProjectConfig{command_specs: command_specs}) do
    if Enum.any?(command_specs, &(&1.profile == :verify)) do
      []
    else
      [
        failure(
          :test_commands,
          "no verify command_specs are configured",
          "Add a verify command spec to .conveyor/config.toml"
        )
      ]
    end
  end

  defp check_policy_files(project_path, %ProjectConfig{} = config) do
    for policy <- ["implement.toml", "verify.toml"],
        path = Path.join([project_path, config.policies_dir, policy]),
        not File.regular?(path) do
      failure(
        :policy_profiles,
        "required policy profile is missing: #{path}",
        "Run mix conveyor.init or restore policy templates"
      )
    end
  end

  defp check_artifact_dirs(project_path, %ProjectConfig{} = config) do
    for dir <- [config.runs_dir, config.blobs_dir],
        path = Path.join(project_path, dir),
        not (File.dir?(path) and writable?(path)) do
      failure(
        :artifact_dir,
        "artifact directory is missing or not writable: #{path}",
        "Create the artifact directory and make it writable"
      )
    end
  end

  defp check_optional_adapters(%ProjectConfig{quality_adapter: "codescent"}, executable?) do
    if executable?.("codescent") do
      []
    else
      [
        failure(
          :codescent,
          "CodeScent is selected as gate-blocking but not installed",
          "Install CodeScent or switch quality_adapter to noop"
        )
      ]
    end
  end

  defp check_optional_adapters(_config, executable?) do
    warnings = []

    warnings =
      if executable?.("pi") do
        warnings
      else
        [
          warning(:pi, "Pi adapter is not installed; required only for live agent runs")
          | warnings
        ]
      end

    warnings =
      if System.get_env("CONVEYOR_PROVIDER_TOKEN") do
        warnings
      else
        [
          warning(
            :provider_credential,
            "provider credential is absent; required only for live agent runs"
          )
          | warnings
        ]
      end

    Enum.reverse(warnings)
  end

  defp check_secret_posture do
    if System.get_env("MIX_ENV") == "prod" do
      [
        failure(
          :secret_posture,
          "doctor is running with MIX_ENV=prod",
          "Run doctor outside production mode"
        )
      ]
    else
      []
    end
  end

  defp default_executable?(name), do: System.find_executable(name) != nil

  defp writable?(path) do
    probe = Path.join(path, ".conveyor-doctor-write-test")

    case File.write(probe, "") do
      :ok ->
        File.rm(probe)
        true

      {:error, _reason} ->
        false
    end
  end

  defp status(findings) do
    if Enum.any?(findings, &(&1.severity == :failure)), do: :failed, else: :passed
  end

  defp format_finding(%Finding{} = finding) do
    line = "#{String.upcase(to_string(finding.severity))} #{finding.check}: #{finding.message}"

    actions =
      Enum.map(finding.next_actions, fn action ->
        "  NextAction: #{action.label} (rerun: #{action.command})"
      end)

    [line | actions]
  end

  defp failure(check, message, action_label) do
    %Finding{
      check: check,
      severity: :failure,
      message: message,
      next_actions: [%NextAction{label: action_label, command: "mix conveyor.doctor"}]
    }
  end

  defp warning(check, message), do: %Finding{check: check, severity: :warning, message: message}
end
