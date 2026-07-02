defmodule Conveyor.AgentRunner.ContainedExec do
  @moduledoc """
  Conveyor-owned containment for the agent subprocess (R11 / U8).

  The station adapters (`Codex`, `ClaudeCode`) no longer shell out to the agent
  CLI directly on the host. Their `default_exec` builds the agent argv and hands
  it here; the argv runs inside a Docker container that applies the declared
  `%Conveyor.Factory.Policy{}` at the OS level:

    * network egress per `network_policy` (default `none` → `--network none`),
    * filesystem writes scoped to the bind-mounted workspace (`--read-only`
      rootfs, only the workspace is `:rw`),
    * a fresh, scrubbed env — `docker run` starts with no host env, so secrets
      like `ANTHROPIC_API_KEY` never cross the boundary unless explicitly
      allowlisted in `env_policy`.

  It reuses the exact hardening the gate sandbox uses (`DockerProfile` /
  `NetworkPolicy`) so the agent and the gate share one boundary, and adds **no
  new runtime dependency**. This is ROADMAP M6's blast-radius isolation pulled
  forward (D1 #1, #5), made load-bearing by the Claude Code default which has no
  CLI-level filesystem confinement of its own.

  Host-path note: `unshare -n` + an egress policy is the D1-sanctioned no-Docker
  variant, but it requires privileges this dogfood host lacks (rootless
  `unshare -n` is denied), so Docker is the shipped path here.

  The container runs as the **host uid:gid** (not a synthetic user) so the agent
  can write its diff to the bind-mounted workspace and the files are owned by the
  operator, not root. Running Conveyor as root is refused — the agent must never
  run as uid 0 (Claude Code also refuses `bypassPermissions` as root).
  """

  alias Conveyor.Factory.Policy
  alias Conveyor.Sandbox.DockerProfile

  @workspace_mount "/workspace"

  @doc """
  Run `argv` inside the contained boundary, returning `{stdout, exit_code}` — the
  same shape a host `System.cmd/3` exec returns, so this is a drop-in for an
  adapter's `default_exec`.
  """
  @spec run([String.t()], String.t(), keyword()) :: {String.t(), non_neg_integer()}
  def run(argv, ws_path, opts) when is_list(argv) and is_binary(ws_path) do
    cmd = Keyword.get(opts, :cmd, &System.cmd/3)
    # KTD1: do NOT merge stderr into stdout on the station path — merged stderr can
    # splice into the stream-json `result` line and silently zero usage/cost.
    cmd.("docker", docker_args(argv, ws_path, opts), stderr_to_stdout: false)
  end

  @doc "The in-container path the workspace is mounted at; adapters that take an explicit working-directory flag should point it here."
  @spec workspace_mount() :: String.t()
  def workspace_mount, do: @workspace_mount

  @doc false
  @spec docker_args([String.t()], String.t(), keyword()) :: [String.t()]
  def docker_args(argv, ws_path, opts) do
    ws_path = Path.expand(ws_path)

    ["run", "--rm", "--workdir", @workspace_mount] ++
      DockerProfile.create_args(network: network_mode(opts), user: host_user!(opts)) ++
      ["--volume", "#{ws_path}:#{@workspace_mount}:#{mount_mode(opts)}"] ++
      creds_mount_args(opts) ++
      env_args(opts) ++
      [image!(opts) | argv]
  end

  # m4b2.2: the reviewer runs with a READ-ONLY workspace mount (it must never mutate the code it
  # judges). Default :rw preserves the implementer, which writes its diff into the workspace.
  defp mount_mode(opts) do
    case Keyword.get(opts, :mount_mode, :rw) do
      :ro -> "ro"
      _rw -> "rw"
    end
  end

  # Neutral in-container path the host credential file is mounted to. Deliberately NOT under
  # $HOME/.claude: a bind-mount there makes docker create a root-owned $HOME/.claude, which the
  # non-root agent then cannot write into (Claude Code's Bash tool needs $HOME/.claude/session-env).
  # The agent image entrypoint copies this file into an agent-owned $HOME/.claude before exec.
  @creds_container_path "/tmp/.conveyor-creds/credentials.json"

  # The container starts with a fresh, scrubbed env, so the agent CLI has no saved login.
  # When the adapter supplies a host credential file (e.g. Claude Code's subscription token),
  # bind-mount ONLY that file read-only — no other host secret or config crosses the boundary.
  # Absent (e.g. Codex, which auths differently), nothing is mounted.
  defp creds_mount_args(opts) do
    case opts[:creds_path] do
      path when is_binary(path) and path != "" ->
        ["--volume", "#{Path.expand(path)}:#{@creds_container_path}:ro"]

      _ ->
        []
    end
  end

  defp network_mode(opts) do
    case opts[:policy] do
      %Policy{network_policy: np} when is_map(np) ->
        # A coding agent needs egress to reach its model API; other values fail closed
        # to :none. `:egress` is open-bridge today (see NetworkPolicy.docker_args/1).
        case Map.get(np, "default", "none") do
          "egress" -> :egress
          _ -> :none
        end

      _ ->
        :none
    end
  end

  # docker run starts a fresh env; we ADD only allowlisted keys, so host secrets
  # never cross the boundary unless an operator explicitly allowlists them. HOME is
  # forced onto the writable tmpfs (/tmp) so the agent CLI has a writable config dir
  # under the --read-only rootfs.
  defp env_args(opts) do
    passthrough =
      for key <- env_allowlist(opts), value = System.get_env(key), do: {key, value}

    Enum.flat_map([{"HOME", "/tmp"} | passthrough], fn {k, v} -> ["--env", "#{k}=#{v}"] end)
  end

  defp env_allowlist(opts) do
    case opts[:policy] do
      %Policy{env_policy: %{"allowlist" => list}} when is_list(list) -> list
      _ -> []
    end
  end

  # Run as the host user so bind-mount writes work and produce host-owned files; refuse
  # uid 0 (the agent must never run as root). Overridable via opts[:user]; uid lookup
  # injectable via opts[:id_cmd] for testing.
  defp host_user!(opts) do
    case Keyword.get(opts, :user) do
      nil ->
        id_cmd = Keyword.get(opts, :id_cmd, &System.cmd/3)
        uid = trimmed!(id_cmd, ["-u"])
        gid = trimmed!(id_cmd, ["-g"])

        if uid == "0" do
          raise ArgumentError,
                "refusing to run the contained agent as root (uid 0); run Conveyor as a non-root user (U8 non-root preflight)"
        end

        "#{uid}:#{gid}"

      user ->
        user
    end
  end

  defp trimmed!(id_cmd, args) do
    {out, 0} = id_cmd.("id", args, [])
    String.trim(out)
  end

  defp image!(opts) do
    Keyword.get(opts, :agent_image) ||
      Application.get_env(:conveyor, :agent_container_image) ||
      raise(
        ArgumentError,
        "no agent container image configured; set `config :conveyor, :agent_container_image` " <>
          "or pass opts[:agent_image]. The image must bundle the agent CLI (U8/U5)."
      )
  end
end
