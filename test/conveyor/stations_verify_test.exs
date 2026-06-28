defmodule Conveyor.StationsVerifyTest do
  # ponytail: this exercises pure venv-resolution (filesystem only, no DB), so plain
  # ExUnit is sufficient — no Conveyor.DataCase / Ash fixture machinery needed.
  use ExUnit.Case, async: true

  alias Conveyor.Stations.Verify

  describe "venv_opts_for/1 (8hx7 hermeticity)" do
    test "resolves venv_bin INTO the slice's own workspace, not samples/tasks_service" do
      ws = temp_dir!("verify-with-venv")
      File.mkdir_p!(Path.join(ws, ".venv/bin"))

      venv = Keyword.fetch!(Verify.venv_opts_for(ws), :venv_bin)

      # Points into THIS workspace, and never at the foreign sample's venv.
      assert venv == Path.join(Path.expand(ws), ".venv/bin")
      refute venv =~ "tasks_service"
    end

    test "omits venv_bin when the workspace has no .venv (no crash)" do
      ws = temp_dir!("verify-no-venv")
      assert Verify.venv_opts_for(ws) == []
    end

    test "returns [] for nil workspace_path (no crash)" do
      assert Verify.venv_opts_for(nil) == []
    end
  end

  defp temp_dir!(label) do
    path =
      Path.join(
        System.tmp_dir!(),
        "conveyor-#{label}-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(path)
    path
  end
end
