defmodule Conveyor.Policy.NormalizedCommand do
  @moduledoc """
  Canonical command shape used before policy evaluation and sandbox execution.
  """

  alias Conveyor.Config.CommandSpec

  @type network :: :none | :loopback | :egress

  @type t :: %__MODULE__{
          executable: String.t(),
          argv: [String.t()],
          cwd: String.t(),
          env_keys: [String.t()],
          stdin_ref: String.t() | nil,
          network: network(),
          write_roots: [String.t()],
          read_roots: [String.t()],
          timeout_ms: pos_integer()
        }

  @enforce_keys [
    :executable,
    :argv,
    :cwd,
    :env_keys,
    :network,
    :write_roots,
    :read_roots,
    :timeout_ms
  ]
  defstruct executable: nil,
            argv: [],
            cwd: nil,
            env_keys: [],
            stdin_ref: nil,
            network: :none,
            write_roots: [],
            read_roots: [],
            timeout_ms: nil

  @spec normalize!(CommandSpec.t() | map() | String.t(), keyword()) :: t()
  def normalize!(command, opts \\ [])

  def normalize!(%CommandSpec{} = command_spec, opts) do
    workspace_root =
      opts
      |> Keyword.fetch!(:workspace_root)
      |> Path.expand()
      |> resolve_terminal_symlink()

    {executable, argv} = split_argv!(command_spec.argv)

    %__MODULE__{
      executable: executable,
      argv: argv,
      cwd: normalize_workspace_path!(workspace_root, command_spec.cwd, "cwd"),
      env_keys: Enum.sort(command_spec.env_allowlist),
      stdin_ref: nil,
      network: command_spec.network,
      write_roots: normalize_write_roots!(workspace_root, Keyword.get(opts, :write_roots, ["."])),
      read_roots: normalize_read_roots!(workspace_root, Keyword.get(opts, :read_roots, ["."])),
      timeout_ms: command_spec.timeout_ms
    }
  end

  def normalize!(%{command: _command}, _opts) do
    raise ArgumentError, "raw shell commands are not normalized"
  end

  def normalize!(%{"command" => _command}, _opts) do
    raise ArgumentError, "raw shell commands are not normalized"
  end

  def normalize!(command, _opts) when is_binary(command) do
    raise ArgumentError, "raw shell commands are not normalized"
  end

  def normalize!(_command, _opts) do
    raise ArgumentError, "expected a Conveyor.Config.CommandSpec"
  end

  defp split_argv!([executable | argv]) when is_binary(executable) and executable != "" do
    if Enum.all?(argv, &is_binary/1) do
      {executable, argv}
    else
      raise ArgumentError, "argv must contain only strings"
    end
  end

  defp split_argv!(_argv), do: raise(ArgumentError, "argv must include an executable")

  defp normalize_write_roots!(workspace_root, write_roots) when is_list(write_roots) do
    write_roots
    |> Enum.map(&normalize_workspace_path!(workspace_root, &1, "write root"))
    |> Enum.uniq()
  end

  defp normalize_write_roots!(_workspace_root, _write_roots) do
    raise ArgumentError, "write_roots must be a list"
  end

  defp normalize_read_roots!(workspace_root, read_roots) when is_list(read_roots) do
    read_roots
    |> Enum.map(&normalize_read_root!(workspace_root, &1))
    |> Enum.uniq()
  end

  defp normalize_read_roots!(_workspace_root, _read_roots) do
    raise ArgumentError, "read_roots must be a list"
  end

  defp normalize_read_root!(workspace_root, path) when is_binary(path) do
    case Path.type(path) do
      :absolute ->
        path
        |> Path.expand()
        |> resolve_terminal_symlink()

      :relative ->
        normalize_workspace_path!(workspace_root, path, "read root")
    end
  end

  defp normalize_read_root!(_workspace_root, _path) do
    raise ArgumentError, "read root must be a string"
  end

  defp normalize_workspace_path!(workspace_root, path, label) when is_binary(path) do
    path =
      workspace_root
      |> Path.join(path)
      |> Path.expand()
      |> resolve_terminal_symlink()

    if under_root?(path, workspace_root) do
      path
    else
      raise ArgumentError, "#{label} escapes workspace"
    end
  end

  defp normalize_workspace_path!(_workspace_root, _path, label) do
    raise ArgumentError, "#{label} must be a string"
  end

  defp resolve_terminal_symlink(path) do
    case File.read_link(path) do
      {:ok, target} ->
        if Path.type(target) == :absolute do
          Path.expand(target)
        else
          path
          |> Path.dirname()
          |> Path.join(target)
          |> Path.expand()
        end

      {:error, _reason} ->
        path
    end
  end

  defp under_root?(path, root), do: path == root or String.starts_with?(path, root <> "/")
end
