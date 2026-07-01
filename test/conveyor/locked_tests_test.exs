defmodule Conveyor.LockedTestsTest do
  use ExUnit.Case, async: true

  alias Conveyor.LockedTests

  setup do
    root = Path.join(System.tmp_dir!(), "locked_tests_#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    {:ok, root: root}
  end

  test "stage! copies a locked test body from .conveyor/locked-tests into the workspace tree",
       %{root: root} do
    File.mkdir_p!(Path.join(root, ".conveyor/locked-tests/tests"))
    body = "def test_x():\n    assert True\n"
    File.write!(Path.join(root, ".conveyor/locked-tests/tests/test_fields.py"), body)

    LockedTests.stage!(root, ["tests/test_fields.py"])

    assert File.read!(Path.join(root, "tests/test_fields.py")) == body
  end

  defp git!(dir, args) do
    {out, 0} = System.cmd("git", ["-C", dir | args], stderr_to_stdout: true)
    String.trim(out)
  end

  defp init_repo!(root) do
    git!(root, ["init", "-q"])
    git!(root, ["config", "user.email", "t@t"])
    git!(root, ["config", "user.name", "t"])
    File.mkdir_p!(Path.join(root, ".conveyor/locked-tests/tests"))

    File.write!(
      Path.join(root, ".conveyor/locked-tests/tests/test_x.py"),
      "def test_x():\n    assert True\n"
    )

    git!(root, ["add", "-A"])
    git!(root, ["commit", "-qm", "base"])
  end

  test "materialize! stages a slice's locked tests and commits them into HEAD", %{root: root} do
    init_repo!(root)
    before = git!(root, ["rev-parse", "HEAD"])

    assert LockedTests.materialize!(root, ["tests/test_x.py::test_x"], "SLICE-001") == :ok

    assert File.exists?(Path.join(root, "tests/test_x.py"))
    assert git!(root, ["status", "--porcelain"]) == ""
    assert git!(root, ["rev-parse", "HEAD"]) != before
    assert git!(root, ["ls-tree", "-r", "--name-only", "HEAD"]) =~ "tests/test_x.py"
  end

  test "materialize! is a no-op when the workspace has no locked-tests directory", %{root: root} do
    git!(root, ["init", "-q"])
    git!(root, ["config", "user.email", "t@t"])
    git!(root, ["config", "user.name", "t"])
    File.write!(Path.join(root, "readme"), "x")
    git!(root, ["add", "-A"])
    git!(root, ["commit", "-qm", "base"])
    before = git!(root, ["rev-parse", "HEAD"])

    assert LockedTests.materialize!(root, ["tests/test_x.py::test_x"], "SLICE-001") == :ok

    assert git!(root, ["rev-parse", "HEAD"]) == before
    refute File.exists?(Path.join(root, "tests/test_x.py"))
  end

  test "paths_for turns required_test_refs (node ids) into distinct sorted file paths" do
    refs = [
      "tests/test_fields.py::test_splits_five_fields",
      "tests/test_fields.py::test_wrong_field_count_raises",
      "tests/test_atom.py::test_single_value"
    ]

    assert LockedTests.paths_for(refs) == ["tests/test_atom.py", "tests/test_fields.py"]
  end
end
