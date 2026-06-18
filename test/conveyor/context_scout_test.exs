defmodule Conveyor.ContextScoutTest do
  use Conveyor.DataCase, async: false

  alias Conveyor.ContextScout
  alias Conveyor.Factory
  alias Conveyor.Factory.ContextPack
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

  defp assert_relevant_file(pack, path, reason_terms) do
    entry = Enum.find(pack.relevant_files, &(&1["path"] == path))

    assert entry, "expected #{path} in #{inspect(pack.relevant_files)}"

    reason = String.downcase(entry["reason"])

    for term <- reason_terms do
      assert String.contains?(reason, term)
    end
  end
end
