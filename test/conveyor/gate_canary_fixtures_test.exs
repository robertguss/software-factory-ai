defmodule Conveyor.GateCanaryFixturesTest do
  use ExUnit.Case, async: true

  @fixture_path "samples/tasks_service/.conveyor/canary/mutants.json"
  @expected_mutants MapSet.new([
                      "patch_unknown_id_returns_200",
                      "completed_not_persisted_to_list",
                      "default_completed_missing",
                      "test_weakened_or_deleted",
                      "new_codescent_high_risk",
                      "forbidden_policy_edit",
                      "repo_prompt_injection_ignored",
                      "tool_output_injection_ignored"
                    ])
  @expected_archetypes MapSet.new([
                         "api_behavior",
                         "state_persistence",
                         "default_contract",
                         "test_integrity",
                         "code_quality",
                         "policy_boundary",
                         "repo_prompt_injection",
                         "tool_output_injection"
                       ])

  test "canary fixture manifest defines known-good patch and initial mutants" do
    manifest = load_manifest!()

    assert manifest["schema_version"] == "conveyor.gate_canary.mutants@1"
    assert manifest["suite_version"] == "canary@1"
    assert manifest["project_key"] == "sample_tasks"

    known_good = Map.fetch!(manifest, "known_good")
    assert known_good["id"] == "known_good_solution"
    assert known_good["expected_gate_status"] == "passed"
    assert patch_exists?(known_good["patch_ref"])

    mutants = Map.fetch!(manifest, "mutants")
    assert MapSet.new(Enum.map(mutants, & &1["id"])) == @expected_mutants
    assert Enum.all?(mutants, & &1["enabled"])
    assert Enum.all?(mutants, &(Map.fetch!(&1, "based_on") == "known_good_solution"))
    assert Enum.all?(mutants, &patch_exists?(Map.fetch!(&1, "patch_ref")))
  end

  test "each mutant has a labeled expected gate catch" do
    manifest = load_manifest!()

    for mutant <- manifest["mutants"] do
      expected = Map.fetch!(mutant, "expected_catch")

      assert is_binary(expected["stage"]) and expected["stage"] != ""
      assert is_binary(expected["category"]) and expected["category"] != ""
      assert is_binary(expected["reason"]) and expected["reason"] != ""
      assert is_binary(mutant["injected_defect"]) and mutant["injected_defect"] != ""
      assert is_list(mutant["valid_stricter_categories"])
    end
  end

  test "mutant corpus declares an archetype coverage matrix" do
    manifest = load_manifest!()
    mutants = Map.fetch!(manifest, "mutants")

    assert MapSet.new(Enum.map(mutants, & &1["archetype"])) == @expected_archetypes

    for mutant <- mutants do
      assert is_binary(mutant["archetype"]) and mutant["archetype"] != ""
      assert is_list(mutant["acceptance_refs"])
      assert mutant["acceptance_refs"] != []
    end
  end

  test "patch fixtures are unified diffs scoped to the sample task fixture" do
    manifest = load_manifest!()

    patch_refs = [
      manifest["known_good"]["patch_ref"] | Enum.map(manifest["mutants"], & &1["patch_ref"])
    ]

    for ref <- patch_refs do
      patch = File.read!(ref)
      assert String.starts_with?(patch, "diff --git ")
      assert patch =~ "samples/tasks_service/"
    end
  end

  test "known-good patch applies to base and mutants apply after known-good" do
    manifest = load_manifest!()

    tmp =
      Path.join(System.tmp_dir!(), "gate-canary-fixtures-#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp)
    File.cp_r!("samples", Path.join(tmp, "samples"))
    on_exit(fn -> File.rm_rf(tmp) end)

    assert_git_apply!(tmp, manifest["known_good"]["patch_ref"], [])

    for mutant <- manifest["mutants"] do
      assert_git_apply!(tmp, mutant["patch_ref"], ["--check"])
    end
  end

  defp load_manifest! do
    @fixture_path
    |> File.read!()
    |> Jason.decode!()
  end

  defp patch_exists?(ref), do: is_binary(ref) and File.regular?(ref)

  defp assert_git_apply!(cwd, patch_ref, args) do
    {output, status} =
      System.cmd("git", ["apply" | args ++ [Path.expand(patch_ref)]],
        cd: cwd,
        stderr_to_stdout: true
      )

    assert status == 0, output
  end
end
