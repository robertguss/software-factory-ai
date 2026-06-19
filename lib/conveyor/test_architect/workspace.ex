defmodule Conveyor.TestArchitect.Workspace do
  @moduledoc """
  Pure workspace contract for the independent Test Architect role.

  The Test Architect may read production source and write only test proposal
  artifacts in an isolated workspace. This module does not materialize
  containers; it emits and checks the deterministic mount contract consumed by
  later integrity/sandbox stages.
  """

  alias Conveyor.Policy.NormalizedCommand

  @forbidden_roles ~w(contract_author critic decomposer implementer)

  @spec materialize!(map()) :: map()
  def materialize!(input) when is_map(input) do
    normalized = stringify_map(input)
    source_root = normalize_root!(Map.fetch!(normalized, "source_root"), "source_root")

    test_workspace_root =
      normalize_root!(Map.fetch!(normalized, "test_workspace_root"), "test_workspace_root")

    reject_overlapping_roots!(source_root, test_workspace_root)

    %{
      "schema_version" => "conveyor.test_architect_workspace@1",
      "slice_id" => Map.fetch!(normalized, "slice_id"),
      "role" => "test_architect",
      "role_view_digest" => Map.fetch!(normalized, "role_view_digest"),
      "contract_digest" => Map.fetch!(normalized, "contract_digest"),
      "authority_effect" => "test_proposal_only",
      "source_mount" => %{
        "host_path" => source_root,
        "mount_path" => "/workspace/source",
        "mode" => "read_only"
      },
      "test_workspace" => %{
        "host_path" => test_workspace_root,
        "mount_path" => "/workspace/test",
        "mode" => "read_write"
      },
      "read_roots" => [source_root, test_workspace_root],
      "write_roots" => [test_workspace_root],
      "forbidden_write_roots" => [source_root],
      "forbidden_roles" => @forbidden_roles,
      "tool_authority" => "test_proposal"
    }
  end

  @spec check_write_attempts(map(), [String.t()]) :: %{
          status: :passed | :blocked,
          findings: [map()]
        }
  def check_write_attempts(contract, attempted_paths)
      when is_map(contract) and is_list(attempted_paths) do
    normalized = stringify_map(contract)
    source_root = get_in(normalized, ["source_mount", "host_path"])
    test_workspace_root = get_in(normalized, ["test_workspace", "host_path"])

    findings =
      attempted_paths
      |> Enum.map(&normalize_path/1)
      |> Enum.flat_map(&write_findings(&1, source_root, test_workspace_root))

    %{status: status(findings), findings: findings}
  end

  @spec normalize_command!(struct() | map(), map(), keyword()) :: NormalizedCommand.t()
  def normalize_command!(command_spec, contract, opts \\ []) do
    normalized = stringify_map(contract)
    source_root = get_in(normalized, ["source_mount", "host_path"])
    test_workspace_root = get_in(normalized, ["test_workspace", "host_path"])

    NormalizedCommand.normalize!(command_spec,
      workspace_root: test_workspace_root,
      write_roots: Keyword.get(opts, :write_roots, ["."]),
      read_roots: Keyword.get(opts, :read_roots, [".", source_root])
    )
  end

  defp write_findings(path, source_root, test_workspace_root) do
    cond do
      under_root?(path, test_workspace_root) ->
        []

      under_root?(path, source_root) ->
        [
          finding(
            "test_architect.production_source_write",
            path,
            "Test Architect attempted to write through the read-only source mount"
          )
        ]

      true ->
        [
          finding(
            "test_architect.mount_escape_write",
            path,
            "Test Architect attempted to write outside the isolated test workspace"
          )
        ]
    end
  end

  defp finding(rule_key, subject_key, message) do
    %{
      rule_key: rule_key,
      severity: :blocking,
      subject_key: subject_key,
      message: message
    }
  end

  defp status([]), do: :passed
  defp status(_findings), do: :blocked

  defp reject_overlapping_roots!(source_root, test_workspace_root) do
    if under_root?(source_root, test_workspace_root) or
         under_root?(test_workspace_root, source_root) do
      raise ArgumentError, "source_root and test_workspace_root must be isolated"
    end
  end

  defp normalize_root!(path, label) when is_binary(path) do
    path
    |> normalize_path()
    |> then(fn normalized ->
      if Path.type(normalized) == :absolute do
        normalized
      else
        raise ArgumentError, "#{label} must be absolute"
      end
    end)
  end

  defp normalize_root!(_path, label), do: raise(ArgumentError, "#{label} must be a string")

  defp normalize_path(path) when is_binary(path) do
    path
    |> Path.expand()
    |> resolve_terminal_symlink()
  end

  defp normalize_path(path),
    do: raise(ArgumentError, "write path must be a string, got: #{inspect(path)}")

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

  defp stringify_map(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), stringify_value(value)} end)
  end

  defp stringify_value(value) when is_map(value), do: stringify_map(value)
  defp stringify_value(values) when is_list(values), do: Enum.map(values, &stringify_value/1)
  defp stringify_value(value), do: value
end
