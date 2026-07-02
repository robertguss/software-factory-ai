defmodule Mix.Tasks.ConveyorAuthorImportTest.StubDrafter do
  @moduledoc false
  @behaviour Conveyor.Planning.PlanFoundry.Drafter

  @impl true
  def draft_plan(_intent, opts), do: {:ok, Keyword.fetch!(opts, :stub_plan)}
end

defmodule Mix.Tasks.ConveyorAuthorImportTest do
  @moduledoc "aaun.2: `mix conveyor.author --import` draft-to-DB handoff via PlanImporter."
  use Conveyor.DataCase, async: false

  import ExUnit.CaptureIO

  alias Conveyor.Factory
  alias Conveyor.Factory.Project
  alias Conveyor.Factory.Slice
  alias Mix.Tasks.ConveyorAuthorImportTest.StubDrafter

  @decomposed "docs/schemas/examples/conveyor.plan.valid.json"
              |> Path.expand()
              |> File.read!()
              |> Jason.decode!()

  @undecomposed %{
    "schema_version" => "conveyor.plan@1",
    "goal" => "List ready issues.",
    "requirements" => [%{"key" => "REQ-001", "text" => "List ready issues sorted by id."}],
    "acceptance_criteria" => [
      %{
        "key" => "AC-001",
        "text" => "Prints unblocked open issues sorted by id.",
        "requirement_refs" => ["REQ-001"],
        "required_test_refs" => ["tests/test_ready.py::test_ready"]
      }
    ],
    "non_goals" => ["No network access."],
    "decisions" => [%{"key" => "DEC-001", "decision" => "Read-only over issues.jsonl."}]
  }

  setup do
    test_pid = self()
    Process.put(:conveyor_author_exit_fun, fn code -> send(test_pid, {:exit, code}) end)
    on_exit(fn -> Process.delete(:conveyor_author_exit_fun) end)
    on_exit(fn -> Process.delete(:conveyor_author_draft_opts) end)

    %{
      out:
        Path.join(System.tmp_dir!(), "author-import-#{System.unique_integer([:positive])}.json")
    }
  end

  defp run_author(args, stub_plan) do
    Process.put(:conveyor_author_draft_opts, drafter: StubDrafter, stub_plan: stub_plan)

    output =
      capture_io(fn ->
        Mix.Task.reenable("conveyor.author")
        Mix.Task.run("conveyor.author", args)
      end)

    json =
      output
      |> String.split("\n", trim: true)
      |> Enum.find(&String.starts_with?(&1, "{"))
      |> Jason.decode!()

    {json, receive_exit()}
  end

  defp receive_exit do
    receive do
      {:exit, code} -> code
    after
      0 -> nil
    end
  end

  test "without --import: drafts the file only and writes no DB rows", %{out: out} do
    {json, code} = run_author(["intent", "--out", out], @undecomposed)

    assert json["status"] == "drafted"
    assert code == 0
    assert Ash.read!(Project, domain: Factory) == []
  end

  test "with --import on a decomposed draft: writes rows and prints the created IDs", %{out: out} do
    {json, code} = run_author(["intent", "--out", out, "--import"], @decomposed)

    assert json["status"] == "imported"
    assert is_binary(json["plan_id"])
    assert json["slice_count"] == 1
    assert json["next"] == "mix conveyor.plan.approve #{json["plan_id"]}"
    assert code == 0

    assert length(Ash.read!(Project, domain: Factory)) == 1
    assert length(Ash.read!(Slice, domain: Factory)) == 1
  end

  test "with --import on an undecomposed draft: refuses with non-zero and writes no rows", %{
    out: out
  } do
    {json, code} = run_author(["intent", "--out", out, "--import"], @undecomposed)

    # A non-runnable draft is refused (rejected at load as schema-invalid without slices, or
    # caught by the decomposed? guard) — never a half-plan.
    assert json["status"] in ["import_failed", "not_decomposed"]
    refute json["status"] == "imported"
    assert code != 0
    assert Ash.read!(Project, domain: Factory) == []
    assert Ash.read!(Slice, domain: Factory) == []
  end
end
