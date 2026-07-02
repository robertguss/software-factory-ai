defmodule Conveyor.Doctor do
  @moduledoc "Operator prerequisite checks for Conveyor projects."

  alias Conveyor.CLI.ExitCodes
  alias Conveyor.CLI.NextAction
  alias Conveyor.Config
  alias Conveyor.Config.ProjectConfig
  alias Conveyor.Doctor.Finding
  alias Conveyor.Doctor.Result
  alias Conveyor.Factory
  alias Conveyor.Factory.ToolchainProfile
  alias Conveyor.Sandbox.DockerProfile

  @type executable_fun :: (String.t() -> boolean())
  @type postgres_fun :: (keyword() -> :ok | {:error, term()})
  @type git_fun :: (String.t(), [String.t()], keyword() -> {String.t(), non_neg_integer()})

  @spec run(Path.t(), keyword()) :: Result.t()
  def run(project_path \\ File.cwd!(), opts \\ []) do
    project_path = Path.expand(project_path)
    executable? = Keyword.get(opts, :executable?, &default_executable?/1)
    postgres_check = Keyword.get(opts, :postgres_check, &default_postgres_check/1)
    git_command = Keyword.get(opts, :git_command, &System.cmd/3)
    docker_command = Keyword.get(opts, :docker_command, &System.cmd/3)
    adapter = resolve_adapter(opts)

    {config, findings} = load_config(project_path)

    findings =
      findings
      |> Kernel.++(check_versions())
      |> Kernel.++(check_oban())
      |> Kernel.++(check_postgres(postgres_check))
      |> Kernel.++(check_docker(executable?))
      |> Kernel.++(check_agent_backend(adapter, executable?, docker_command))
      |> Kernel.++(check_toolchain_profiles(executable?, docker_command))
      |> Kernel.++(check_sandbox_constraints(executable?, docker_command))
      |> Kernel.++(check_policy_toml(project_path))
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

    # Postgrex needs :postgrex/:db_connection started before start_link/1 — the
    # mix task does not boot the app, so start them here. Without this the
    # connection pool registration crashes on a missing DBConnection.Watcher and
    # the linked exit takes the whole doctor run down.
    with {:ok, _apps} <- Application.ensure_all_started(:postgrex) do
      verify_postgres_connection(opts)
    end
  rescue
    error -> {:error, error}
  catch
    :exit, reason -> {:error, reason}
  end

  defp verify_postgres_connection(opts) do
    case Postgrex.start_link(opts) do
      {:ok, pid} ->
        try do
          # start_link/1 returns {:ok, pid} even when Postgres is unreachable
          # (it connects asynchronously), so actually issue a query to confirm
          # reachability rather than trusting the pid alone.
          case Postgrex.query(pid, "SELECT 1", [], timeout: Keyword.fetch!(opts, :timeout)) do
            {:ok, _result} -> :ok
            {:error, reason} -> {:error, reason}
          end
        after
          GenServer.stop(pid)
        end

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

  # tt6v.2: each declared toolchain profile's pinned image must be present locally (reproducibility
  # identity — "passes here, fails there" is exactly what pinned per-language images prevent). A
  # missing image is a warning, not a failure: the :local backend does not need it, and it is
  # pullable. Skipped when docker is absent (check_docker already reports that) or the DB is
  # unreadable (check_postgres reports that).
  defp check_toolchain_profiles(executable?, docker_command) do
    if executable?.("docker") do
      Enum.flat_map(toolchain_profiles(), &profile_image_finding(&1, docker_command))
    else
      []
    end
  end

  defp toolchain_profiles do
    Ash.read!(ToolchainProfile, domain: Factory)
  rescue
    _error -> []
  end

  defp profile_image_finding(profile, docker_command) do
    case docker_command.("docker", ["image", "inspect", profile.image_ref],
           stderr_to_stdout: true
         ) do
      {_output, 0} ->
        []

      {_output, _nonzero} ->
        [
          warning(
            :toolchain_profile_image,
            "Toolchain profile #{profile.key} (#{profile.language}) image #{profile.image_ref} " <>
              "is not present locally",
            "docker pull #{profile.image_ref}"
          )
        ]
    end
  end

  # mmxr.4 (never-lie): validate the ACTIVE agent backend's prereqs, not a stale vendor. The default
  # is contained Claude Code (PRs #39/#40); `--adapter`/`config :conveyor, :agent_adapter` selects
  # another. Codex prereqs are only checked when codex is the selected backend.
  @spec resolve_adapter(keyword()) :: String.t()
  defp resolve_adapter(opts) do
    (Keyword.get(opts, :adapter) || Application.get_env(:conveyor, :agent_adapter, "claude_code"))
    |> to_string()
  end

  defp check_agent_backend("codex", executable?, _docker_command) do
    require_cli(
      executable?,
      "codex",
      "Codex is the selected agent backend but the `codex` CLI is not installed",
      "Install the Codex CLI and log in, or select another agent backend"
    )
  end

  defp check_agent_backend(_claude_code, executable?, docker_command) do
    cli =
      require_cli(
        executable?,
        "claude",
        "Claude Code is the default agent backend but the `claude` CLI is not installed",
        "Install Claude Code and authenticate (claude login)"
      )

    cli ++ check_agent_image(executable?, docker_command)
  end

  defp require_cli(executable?, command, message, action_label) do
    if executable?.(command),
      do: [],
      else: [failure(String.to_atom("agent_backend_#{command}"), message, action_label)]
  end

  # The contained backend needs its prebuilt image; a warning (buildable on-demand), matching the
  # toolchain-profile image check rather than hard-failing a first run before the build step.
  defp check_agent_image(executable?, docker_command) do
    case Application.get_env(:conveyor, :agent_container_image) do
      nil ->
        [
          warning(
            :agent_image,
            "No agent container image is configured; the contained backend cannot run",
            "Set `config :conveyor, :agent_container_image`"
          )
        ]

      image when is_binary(image) ->
        if executable?.("docker"), do: agent_image_finding(image, docker_command), else: []
    end
  end

  defp agent_image_finding(image, docker_command) do
    case docker_command.("docker", ["image", "inspect", image], stderr_to_stdout: true) do
      {_output, 0} ->
        []

      {_output, _nonzero} ->
        [
          warning(
            :agent_image,
            "Agent container image #{image} is not present locally; the contained backend needs it",
            "docker build -t #{image} toolchains/agent-image"
          )
        ]
    end
  end

  # a7kf tie-in: a malformed policy TOML must be caught pre-flight, not at slice 1 of a night run.
  defp check_policy_toml(project_path) do
    project_path
    |> Path.join(".conveyor/policies/*.toml")
    |> Path.wildcard()
    |> Enum.flat_map(&policy_toml_finding/1)
  end

  defp policy_toml_finding(path) do
    case File.read(path) do
      {:ok, content} -> policy_toml_parse_finding(path, content)
      {:error, _posix} -> []
    end
  end

  defp policy_toml_parse_finding(path, content) do
    case decode_policy_toml(content) do
      {:ok, _decoded} ->
        []

      {:error, reason} ->
        [
          failure(
            :policy_toml,
            "Policy file #{Path.basename(path)} is not valid TOML: #{reason}",
            "Fix the TOML syntax in #{path}"
          )
        ]
    end
  end

  defp decode_policy_toml(content) do
    case TomlElixir.decode(content) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, reason} -> {:error, inspect(reason)}
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp check_sandbox_constraints(executable?, docker_command) do
    if executable?.("docker") do
      case docker_command.("docker", ["info", "--format", "{{json .SecurityOptions}}"],
             stderr_to_stdout: true
           ) do
        {output, 0} ->
          sandbox_constraint_findings(output)

        {output, status} ->
          [
            failure(
              :sandbox_constraints,
              "Docker security options could not be inspected: #{String.trim(output)} (#{status})",
              "Start Docker with seccomp/no-new-privileges support or select a compatible sandbox profile"
            )
          ]
      end
    else
      []
    end
  end

  defp sandbox_constraint_findings(security_options) do
    failures =
      DockerProfile.required_security_options()
      |> Enum.reject(&String.contains?(security_options, &1))
      |> Enum.map(fn option ->
        failure(
          :sandbox_constraints,
          "Docker required security option is unavailable: #{option}",
          "Enable #{option} support or select a compatible sandbox profile"
        )
      end)

    rootless_warnings =
      if String.contains?(security_options, "rootless") do
        []
      else
        [warning(:sandbox_rootless, "Docker rootless mode is not active; rootless is preferred")]
      end

    failures ++ rootless_warnings
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
    for policy <- [
          "explore.toml",
          "implement.toml",
          "maintenance.toml",
          "release.toml",
          "verify.toml"
        ],
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

  defp warning(check, message, action_label) do
    %Finding{
      check: check,
      severity: :warning,
      message: message,
      next_actions: [%NextAction{label: action_label, command: action_label}]
    }
  end
end
