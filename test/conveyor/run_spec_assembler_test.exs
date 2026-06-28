defmodule Conveyor.RunSpecAssemblerTest do
  @moduledoc """
  Focused coverage for the default DiffPolicy that RunSpecAssembler synthesizes from a slice's
  `likely_files` (KTD-6): tests/ is locked into `protected_path_globs`, stripped out of
  `allowed_path_globs`, and excluded from the `max_files_changed` budget — and the two glob
  sets are always disjoint.
  """
  use Conveyor.DataCase, async: false

  alias Conveyor.Factory
  alias Conveyor.Factory.DiffPolicy
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Project
  alias Conveyor.Factory.Slice
  alias Conveyor.Planning.RunSpecAssembler

  test "locks tests/**, strips the locked test out of allowed, and budgets only the source set" do
    slice = assemble_with_likely_files!(["src/foo.py", "tests/test_foo.py"])
    diff_policy = default_diff_policy!(slice.id)

    # (1) tests/** is locked into protected (the matcher's `**` spans `/`, so this also covers
    # tests/golden/digest.md) — defense-in-depth alongside DiffScope out_of_scope.
    assert "tests/**" in diff_policy.protected_path_globs

    # (2) the locked test is stripped from allowed; the real source file stays.
    assert "src/foo.py" in diff_policy.allowed_path_globs
    refute "tests/test_foo.py" in diff_policy.allowed_path_globs

    # (3) the budget counts only the stripped allowed set (1 source file), never the locked test.
    assert diff_policy.max_files_changed == 1

    # (4) invariant: no path appears in both allowed and protected.
    assert disjoint?(diff_policy)
  end

  test "a slice with no test files keeps allowed and budget intact while still locking tests/**" do
    slice = assemble_with_likely_files!(["src/foo.py", "src/bar.py"])
    diff_policy = default_diff_policy!(slice.id)

    # No spurious shrink: every source file is still allowed and the budget is unchanged.
    assert diff_policy.allowed_path_globs == ["src/foo.py", "src/bar.py"]
    assert diff_policy.max_files_changed == 2

    # tests/** is still locked even when the slice never named a test file.
    assert "tests/**" in diff_policy.protected_path_globs
    assert disjoint?(diff_policy)
  end

  defp disjoint?(%DiffPolicy{} = diff_policy) do
    MapSet.disjoint?(
      MapSet.new(diff_policy.allowed_path_globs),
      MapSet.new(diff_policy.protected_path_globs)
    )
  end

  defp default_diff_policy!(slice_id) do
    DiffPolicy
    |> Ash.read!(domain: Factory)
    |> Enum.find(&(&1.slice_id == slice_id)) ||
      raise "no DiffPolicy was synthesized for slice #{slice_id}"
  end

  # Assembles a RunSpec for a one-slice plan with the given `likely_files`, which is the only
  # public seam that reaches the private `create_default_diff_policy!/1`. Returns the slice so the
  # caller can read back its synthesized DiffPolicy. `base_commit` is supplied explicitly so no git
  # workspace is needed (assemble! never executes stations; it only lowers + persists the spec).
  defp assemble_with_likely_files!(likely_files) do
    project =
      Ash.create!(
        Project,
        %{name: "DiffPolicy sample", local_path: temp_dir!(), default_branch: "main"},
        domain: Factory
      )

    plan =
      Ash.create!(
        Plan,
        %{
          project_id: project.id,
          title: "DiffPolicy plan",
          intent: "Synthesize a default diff policy.",
          source_document: "docs/diff_policy.md",
          normalized_contract: normalized_contract(likely_files),
          contract_sha256: digest("plan"),
          status: :handoff_ready
        },
        domain: Factory
      )

    epic =
      Ash.create!(
        Epic,
        %{plan_id: plan.id, title: "DiffPolicy epic", description: "Single slice."},
        domain: Factory
      )

    slice =
      Ash.create!(
        Slice,
        %{
          epic_id: epic.id,
          title: "Slice under policy",
          position: 1,
          risk: "low",
          autonomy_level: "L1",
          source_refs: ["REQ-001"],
          likely_files: likely_files,
          conflict_domains: ["model_io"]
        },
        domain: Factory
      )

    RunSpecAssembler.assemble!(slice,
      work_graph: work_graph(likely_files),
      base_commit: digest("base"),
      agent_adapter: Conveyor.AgentRunner.ReferenceSolution
    )

    slice
  end

  defp normalized_contract(likely_files) do
    %{
      "schema_version" => "conveyor.plan@1",
      "goal" => "Bound the diff scope for a slice.",
      "non_goals" => ["Do not implement command-line reporting."],
      "requirements" => [%{"key" => "REQ-001", "risk" => "low"}],
      "acceptance_criteria" => [
        %{
          "key" => "AC-001",
          "text" => "The frozen corpus counts stay stable.",
          "requirement_refs" => ["REQ-001"],
          "required_test_refs" => ["tests/test_foo.py::test_counts_stable"]
        }
      ],
      "verification_commands" => [
        %{"key" => "pytest", "argv" => ["pytest", "-q"], "profile" => "verify"}
      ],
      "slices" => [
        %{
          "key" => "SLICE-001",
          "title" => "Slice under policy",
          "requirement_refs" => ["REQ-001"],
          "likely_files" => likely_files,
          "conflict_domains" => ["model_io"],
          "autonomy_ceiling" => "L1"
        }
      ]
    }
  end

  defp work_graph(likely_files) do
    %{
      "schema_version" => "conveyor.work_graph@2",
      "slices" => [
        %{
          "stable_key" => "SLICE-001",
          "title" => "Slice under policy",
          "requirement_refs" => ["REQ-001"],
          "likely_files" => likely_files,
          "conflict_domains" => ["model_io"]
        }
      ]
    }
  end

  defp temp_dir! do
    path =
      Path.join(
        System.tmp_dir!(),
        "conveyor-diff-policy-#{System.system_time(:nanosecond)}-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(path)
    path
  end

  defp digest(label), do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, label), case: :lower)
end
