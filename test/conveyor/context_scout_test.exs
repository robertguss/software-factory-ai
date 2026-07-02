defmodule Conveyor.ContextScoutTest do
  use Conveyor.DataCase, async: false

  alias Conveyor.ContextScout
  alias Conveyor.Factory
  alias Conveyor.Factory.ContextPack
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Project
  alias Conveyor.Factory.Slice
  alias Conveyor.SampleTasksSeed

  @base_commit String.duplicate("a", 40)

  setup do
    Process.put(:conveyor_seed_sample_git_fun, fn _repo_root, ["rev-parse", "HEAD"] ->
      {@base_commit <> "\n", 0}
    end)

    on_exit(fn -> Process.delete(:conveyor_seed_sample_git_fun) end)

    %{seed: SampleTasksSeed.seed!(base_commit: @base_commit)}
  end

  test "writes a cited context pack with router model tests and confidence", %{seed: seed} do
    pack = ContextScout.run!(seed.slice)

    assert pack.slice_id == seed.slice.id
    assert pack.scout_version == "context-scout@1"
    assert Decimal.compare(pack.confidence, Decimal.new("0.80")) in [:eq, :gt]

    assert "GET /tasks" in pack.key_interfaces
    assert "PATCH /tasks/{id}" in pack.key_interfaces
    assert "tests/test_tasks_api.py" in pack.existing_tests
    assert "pytest -q" in pack.suggested_validation
    assert pack.code_quality_refs == []

    assert_relevant_file(
      pack,
      "tasks_service/main.py",
      ["router", "model"]
    )

    assert_relevant_file(
      pack,
      "tests/test_tasks_api.py",
      ["tests", "acceptance"]
    )

    assert Enum.any?(pack.risks, &String.contains?(&1, "Completed state"))
    assert [%ContextPack{id: id}] = Ash.read!(ContextPack, domain: Factory)
    assert id == pack.id
  end

  test "can scout by slice id", %{seed: seed} do
    pack =
      ContextScout.run!(seed.slice.id, code_quality_refs: ["artifacts/quality/baseline.json"])

    assert pack.slice_id == seed.slice.id
    assert pack.code_quality_refs == ["artifacts/quality/baseline.json"]
  end

  test "includes bounded, redacted, deterministic excerpts for top-K source files (aabq.1)", %{
    seed: seed
  } do
    pack = ContextScout.run!(seed.slice)

    excerpt = Enum.find(pack.file_excerpts, &(&1["path"] == "tasks_service/main.py"))
    assert excerpt, "expected an excerpt for main.py in #{inspect(pack.file_excerpts)}"
    assert is_binary(excerpt["excerpt"]) and excerpt["excerpt"] != ""
    assert excerpt["bytes"] == byte_size(excerpt["excerpt"])
    # only source files get excerpts (no configs/tests dumped verbatim)
    assert Enum.all?(
             pack.file_excerpts,
             &(Path.extname(&1["path"]) in ~w(.ex .exs .js .jsx .py .ts .tsx))
           )

    # deterministic: a second scout of the same tree yields byte-identical excerpts (replayable).
    assert ContextScout.run!(seed.slice).file_excerpts == pack.file_excerpts
  end

  test "excerpts honor the byte budget and truncate deterministically (aabq.1)", %{seed: seed} do
    pack = ContextScout.run!(seed.slice, excerpt_max_files: 2, excerpt_max_bytes: 40)

    assert length(pack.file_excerpts) <= 2
    assert Enum.all?(pack.file_excerpts, &(&1["bytes"] <= 40))
    assert Enum.any?(pack.file_excerpts, & &1["truncated"])
  end

  test "a planted secret never leaks into an excerpt (aabq.1)" do
    # Isolated temp workspace — never mutate the committed sample tree.
    root = Path.join(System.tmp_dir!(), "scout-secret-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(root, "svc"))
    File.write!(Path.join(root, "svc/app.py"), "# key AKIAIOSFODNN7EXAMPLE\nprint('hi')\n")
    on_exit(fn -> File.rm_rf!(root) end)

    slice = temp_project_slice!(root, ["svc/app.py"])
    pack = ContextScout.run!(slice)
    excerpt = Enum.find(pack.file_excerpts, &(&1["path"] == "svc/app.py"))

    assert excerpt, "expected an excerpt for svc/app.py in #{inspect(pack.file_excerpts)}"
    refute excerpt["excerpt"] =~ "AKIAIOSFODNN7EXAMPLE"
    assert excerpt["excerpt"] =~ "REDACTED"
  end

  test "selects a non-Python entrypoint language-neutrally and hands off its signature (aabq.2)" do
    root = Path.join(System.tmp_dir!(), "scout-lang-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    File.write!(Path.join(root, "server.js"), "export function handler(req) {\n  return req\n}\n")
    on_exit(fn -> File.rm_rf!(root) end)

    slice = temp_project_slice!(root, [])
    # brief with an HTTP-verb interface hint drives the entrypoint heuristic (no likely_files)
    brief_with_interfaces!(slice, ["GET /orders"])

    pack = ContextScout.run!(slice)
    paths = Enum.map(pack.relevant_files, & &1["path"])

    # server.js is picked by stem, not a hardcoded *.py name (de-Python-bias).
    assert "server.js" in paths, "expected server.js selected, got #{inspect(paths)}"

    excerpt = Enum.find(pack.file_excerpts, &(&1["path"] == "server.js"))
    assert excerpt["excerpt"] =~ "export function handler"
  end

  defp brief_with_interfaces!(slice, key_interfaces) do
    Ash.create!(
      Conveyor.Factory.AgentBrief,
      %{
        slice_id: slice.id,
        version: 1,
        current_behavior: "none",
        desired_behavior: "handle orders",
        key_interfaces: key_interfaces,
        out_of_scope: [],
        risk: "medium",
        acceptance_criteria: [],
        required_tests: [],
        verification_commands: [],
        non_goals: [],
        locked_at: DateTime.utc_now(:microsecond),
        locked_by: "planner",
        contract_sha256: "sha256:brief"
      },
      domain: Factory
    )
  end

  # A minimal project→plan→epic→slice pointing at `root`, with `likely_files` so the scout selects
  # the fixture file. No AgentBrief (source selection falls back to likely_files).
  defp temp_project_slice!(root, likely_files) do
    project =
      Ash.create!(
        Project,
        %{
          name: "scout-temp",
          local_path: root,
          default_branch: "main",
          default_autonomy_level: 2
        },
        domain: Factory
      )

    plan =
      Ash.create!(
        Plan,
        %{
          project_id: project.id,
          title: "scout temp",
          intent: "scout",
          source_document: "t",
          normalized_contract: %{"goal" => "t"},
          contract_sha256: "sha256:t",
          status: :handoff_ready
        },
        domain: Factory
      )

    epic = Ash.create!(Epic, %{plan_id: plan.id, title: "e", description: "d"}, domain: Factory)

    Ash.create!(
      Slice,
      %{
        epic_id: epic.id,
        title: "s",
        position: 1,
        risk: "medium",
        autonomy_level: "L2",
        source_refs: [],
        likely_files: likely_files,
        conflict_domains: []
      },
      domain: Factory
    )
  end

  defp assert_relevant_file(pack, path, reason_terms) do
    entry = Enum.find(pack.relevant_files, &(&1["path"] == path))

    assert entry, "expected #{path} in #{inspect(pack.relevant_files)}"

    reason = String.downcase(entry["reason"])

    for term <- reason_terms do
      assert String.contains?(reason, term)
    end
  end
end
