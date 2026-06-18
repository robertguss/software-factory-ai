defmodule Conveyor.GateStagesScopeTest do
  use ExUnit.Case, async: true

  alias Conveyor.Factory.DiffPolicy
  alias Conveyor.Factory.PatchSet
  alias Conveyor.Factory.RunAttempt
  alias Conveyor.Factory.RunSpec
  alias Conveyor.Gate
  alias Conveyor.Gate.Stages.DiffScope
  alias Conveyor.Gate.Stages.WorkspaceIntegrity

  test "workspace integrity fails closed on locked paths and missing tree digest" do
    result =
      WorkspaceIntegrity.run(%{
        run_spec: %RunSpec{base_commit: "base-1"},
        run_attempt: %RunAttempt{base_commit: "base-1"},
        patch_set: %PatchSet{
          base_commit: "base-1",
          patch_ref: "patches/attempt.patch",
          applies_cleanly: true,
          touches_locked_paths: true
        }
      })

    assert result.status == :failed
    categories = Enum.map(result.findings, & &1["category"])
    assert "locked_path_touched" in categories
    assert "missing_head_tree_sha256" in categories
  end

  test "workspace integrity passes when base patch and tree digest match" do
    result =
      WorkspaceIntegrity.run(%{
        head_tree_sha256: "sha256:tree",
        run_spec: %RunSpec{base_commit: "base-1"},
        run_attempt: %RunAttempt{base_commit: "base-1"},
        patch_set: %PatchSet{
          base_commit: "base-1",
          patch_ref: "patches/attempt.patch",
          applies_cleanly: true,
          touches_locked_paths: false
        }
      })

    assert result.status == :passed
    assert result.output_digest == "sha256:tree"
  end

  test "workspace integrity flags a patch set that does not apply cleanly" do
    result =
      WorkspaceIntegrity.run(%{
        head_tree_sha256: "sha256:tree",
        run_spec: %RunSpec{base_commit: "base-1"},
        run_attempt: %RunAttempt{base_commit: "base-1"},
        patch_set: %PatchSet{
          base_commit: "base-1",
          patch_ref: "patches/attempt.patch",
          applies_cleanly: false,
          touches_locked_paths: false
        }
      })

    assert result.status == :failed
    assert "patch_apply_failed" in Enum.map(result.findings, & &1["category"])
  end

  test "diff scope fails for out-of-policy paths size and forbidden change classes" do
    result =
      DiffScope.run(%{
        patch_set: %PatchSet{
          patch_ref: "patches/attempt.patch",
          patch_sha256: "sha256:patch",
          changed_files: [
            "lib/tasks_api.ex",
            "mix.lock",
            "priv/repo/migrations/20260618000000_change.exs",
            "tmp/outside.txt"
          ],
          lines_added: 120,
          lines_deleted: 12
        },
        diff_policy: %DiffPolicy{
          allowed_path_globs: ["lib/**", "test/**"],
          protected_path_globs: ["lib/locked/**"],
          max_files_changed: 3,
          max_lines_added: 100,
          max_lines_deleted: 10,
          dependency_changes_allowed: false,
          migrations_allowed: false,
          generated_files_allowed: false,
          public_api_changes_allowed: false
        }
      })

    assert result.status == :failed
    categories = MapSet.new(Enum.map(result.findings, & &1["category"]))
    assert MapSet.member?(categories, "out_of_scope_path")
    assert MapSet.member?(categories, "max_files_changed")
    assert MapSet.member?(categories, "max_lines_added")
    assert MapSet.member?(categories, "max_lines_deleted")
    assert MapSet.member?(categories, "dependency_change")
    assert MapSet.member?(categories, "migration_change")
    assert MapSet.member?(categories, "public_api_change")
  end

  test "workspace and diff scope stages compose through the gate framework" do
    result =
      Gate.run!(
        %{
          head_tree_sha256: "sha256:tree",
          gate_code_sha256: "sha256:gate",
          policy_sha256: "sha256:policy",
          contract_lock_sha256: "sha256:contract",
          run_spec: %RunSpec{base_commit: "base-1"},
          run_attempt: %RunAttempt{base_commit: "base-1"},
          patch_set: %PatchSet{
            base_commit: "base-1",
            patch_ref: "patches/attempt.patch",
            patch_sha256: "sha256:patch",
            changed_files: ["lib/tasks/service.ex", "test/tasks/service_test.exs"],
            lines_added: 20,
            lines_deleted: 2,
            applies_cleanly: true,
            touches_locked_paths: false
          },
          diff_policy: %DiffPolicy{
            allowed_path_globs: ["lib/**", "test/**"],
            max_files_changed: 4,
            max_lines_added: 50,
            max_lines_deleted: 10,
            dependency_changes_allowed: false,
            migrations_allowed: false,
            generated_files_allowed: false,
            public_api_changes_allowed: false
          }
        },
        [
          %{key: "workspace_integrity", module: WorkspaceIntegrity},
          %{key: "diff_scope", module: DiffScope}
        ]
      )

    assert result.passed?
    assert Enum.map(result.stages, & &1.status) == [:passed, :passed]
  end
end
