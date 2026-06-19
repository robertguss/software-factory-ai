defmodule Conveyor.TestArchitectWorkspaceTest do
  use ExUnit.Case, async: true

  alias Conveyor.Config.CommandSpec
  alias Conveyor.TestArchitect.Workspace

  test "materializes a read-only source mount and isolated test-only workspace" do
    source_root = temp_dir!("source")
    test_workspace_root = temp_dir!("test-workspace")

    contract =
      Workspace.materialize!(%{
        slice_id: "SLC-001",
        source_root: source_root,
        test_workspace_root: test_workspace_root,
        role_view_digest: "sha256:role-view",
        contract_digest: "sha256:agent-brief"
      })

    assert contract["schema_version"] == "conveyor.test_architect_workspace@1"
    assert contract["role"] == "test_architect"
    assert contract["authority_effect"] == "test_proposal_only"
    assert contract["source_mount"]["host_path"] == source_root
    assert contract["source_mount"]["mode"] == "read_only"
    assert contract["test_workspace"]["host_path"] == test_workspace_root
    assert contract["test_workspace"]["mode"] == "read_write"
    assert contract["write_roots"] == [test_workspace_root]
    assert contract["read_roots"] == [source_root, test_workspace_root]

    assert contract["forbidden_roles"] == [
             "contract_author",
             "critic",
             "decomposer",
             "implementer"
           ]
  end

  test "flags production source writes and mount escapes" do
    source_root = temp_dir!("source-boundary")
    test_workspace_root = temp_dir!("test-boundary")
    outside_root = temp_dir!("outside")

    contract =
      Workspace.materialize!(%{
        slice_id: "SLC-002",
        source_root: source_root,
        test_workspace_root: test_workspace_root,
        role_view_digest: "sha256:role-view",
        contract_digest: "sha256:agent-brief"
      })

    result =
      Workspace.check_write_attempts(contract, [
        Path.join(test_workspace_root, "tests/tasks_test.exs"),
        Path.join(source_root, "lib/tasks.ex"),
        Path.join(outside_root, "scratch.txt")
      ])

    assert result.status == :blocked

    assert Enum.any?(
             result.findings,
             &(&1.rule_key == "test_architect.production_source_write")
           )

    assert Enum.any?(result.findings, &(&1.rule_key == "test_architect.mount_escape_write"))
    refute Enum.any?(result.findings, &String.ends_with?(&1.subject_key, "tasks_test.exs"))
  end

  test "normalizes commands with source read access and test-only write roots" do
    source_root = temp_dir!("source-command")
    test_workspace_root = temp_dir!("test-command")

    contract =
      Workspace.materialize!(%{
        slice_id: "SLC-003",
        source_root: source_root,
        test_workspace_root: test_workspace_root,
        role_view_digest: "sha256:role-view",
        contract_digest: "sha256:agent-brief"
      })

    command = %CommandSpec{
      key: "pytest",
      argv: ["pytest", "-q", "tests"],
      cwd: ".",
      profile: :verify,
      network: :none,
      env_allowlist: ["PYTHONPATH"],
      timeout_ms: 120_000
    }

    normalized = Workspace.normalize_command!(command, contract)

    assert normalized.cwd == test_workspace_root
    assert normalized.write_roots == [test_workspace_root]
    assert normalized.read_roots == [test_workspace_root, source_root]
    assert normalized.network == :none

    assert_raise ArgumentError, ~r/write root escapes workspace/, fn ->
      Workspace.normalize_command!(command, contract, write_roots: ["../source-command"])
    end
  end

  defp temp_dir!(label) do
    path =
      Path.join(
        System.tmp_dir!(),
        "conveyor-test-architect-workspace-#{label}-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(path)
    Path.expand(path)
  end
end
