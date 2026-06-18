defmodule Conveyor.Policy.NormalizedCommandTest do
  use ExUnit.Case, async: true

  alias Conveyor.Config.CommandSpec
  alias Conveyor.Policy.NormalizedCommand

  test "normalizes a command spec deterministically" do
    workspace_root = temp_dir!("workspace")

    command_spec = %CommandSpec{
      key: "pytest",
      argv: ["pytest", "-q"],
      cwd: ".",
      profile: :verify,
      network: :none,
      env_allowlist: ["PYTHONPATH"],
      timeout_ms: 120_000
    }

    opts = [
      workspace_root: workspace_root,
      read_roots: [".", "/conveyor/locked_tests"],
      write_roots: ["."]
    ]

    first = NormalizedCommand.normalize!(command_spec, opts)
    second = NormalizedCommand.normalize!(command_spec, opts)

    assert first == second
    assert first.executable == "pytest"
    assert first.argv == ["-q"]
    assert first.cwd == workspace_root
    assert first.env_keys == ["PYTHONPATH"]
    assert first.network == :none
    assert first.timeout_ms == 120_000
    assert first.write_roots == [workspace_root]
    assert first.read_roots == [workspace_root, "/conveyor/locked_tests"]
  end

  test "rejects raw shell commands" do
    workspace_root = temp_dir!("raw-shell")

    assert_raise ArgumentError, ~r/raw shell commands are not normalized/, fn ->
      NormalizedCommand.normalize!(
        %{command: "pytest -q", profile: :verify},
        workspace_root: workspace_root
      )
    end
  end

  test "rejects cwd symlinks that escape the workspace" do
    workspace_root = temp_dir!("cwd-workspace")
    outside = temp_dir!("outside-cwd")
    File.ln_s!(outside, Path.join(workspace_root, "outside"))

    command_spec = %CommandSpec{
      key: "pytest",
      argv: ["pytest", "-q"],
      cwd: "outside",
      profile: :verify
    }

    assert_raise ArgumentError, ~r/cwd escapes workspace/, fn ->
      NormalizedCommand.normalize!(command_spec, workspace_root: workspace_root)
    end
  end

  test "rejects write roots that escape through symlinks" do
    workspace_root = temp_dir!("write-workspace")
    outside = temp_dir!("outside-write")
    File.ln_s!(outside, Path.join(workspace_root, "cache"))

    command_spec = %CommandSpec{
      key: "pytest",
      argv: ["pytest", "-q"],
      cwd: ".",
      profile: :verify
    }

    assert_raise ArgumentError, ~r/write root escapes workspace/, fn ->
      NormalizedCommand.normalize!(command_spec,
        workspace_root: workspace_root,
        write_roots: ["cache"]
      )
    end
  end

  defp temp_dir!(label) do
    path =
      Path.join(
        System.tmp_dir!(),
        "conveyor-normalized-command-#{label}-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(path)
    Path.expand(path)
  end
end
