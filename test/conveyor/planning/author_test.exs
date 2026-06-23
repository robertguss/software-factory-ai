defmodule Conveyor.Planning.AuthorTest.StubDrafter do
  @moduledoc false
  @behaviour Conveyor.Planning.PlanFoundry.Drafter

  @impl true
  def draft_plan(_intent, opts), do: {:ok, Keyword.fetch!(opts, :stub_plan)}
end

defmodule Conveyor.Planning.AuthorTest.FailingDrafter do
  @moduledoc false
  @behaviour Conveyor.Planning.PlanFoundry.Drafter

  @impl true
  def draft_plan(_intent, _opts), do: {:error, :drafter_unavailable}
end

defmodule Conveyor.Planning.AuthorTest do
  @moduledoc """
  ADR-27 (M5) — `Conveyor.Planning.Author` + the `mix conveyor.author` task. Exercised
  through an injected `Drafter` (no live agent). The drafter/audit pattern mirrors
  `Conveyor.Planning.PlanFoundryTest`.
  """
  use ExUnit.Case, async: false

  alias Conveyor.CLI.ExitCodes
  alias Conveyor.Planning.Author
  alias Conveyor.Planning.AuthorTest.{FailingDrafter, StubDrafter}

  defp tmp_path do
    Path.join(System.tmp_dir!(), "conveyor_author_#{System.unique_integer([:positive])}.json")
  end

  # A structurally clean conveyor.plan@1 draft (passes StructuralAudit with no findings).
  defp clean_plan do
    %{
      "goal" => "Print the set of ready issues.",
      "requirements" => [%{"key" => "REQ-001", "text" => "List ready issues sorted by id."}],
      "acceptance_criteria" => [
        %{
          "key" => "AC-001",
          "text" => "Given a corpus, prints unblocked open issues sorted by id.",
          "requirement_refs" => ["REQ-001"],
          "required_test_refs" => ["tests/test_ready.py::test_ready"]
        }
      ],
      "non_goals" => ["No network access."],
      "decisions" => [%{"key" => "DEC-001", "decision" => "Read-only over issues.jsonl."}]
    }
  end

  # The clean plan plus a requirement with no acceptance criterion -> one blocking
  # audit finding naming REQ-002.
  defp gap_plan do
    plan = clean_plan()

    %{
      plan
      | "requirements" =>
          plan["requirements"] ++ [%{"key" => "REQ-002", "text" => "Show velocity."}]
    }
  end

  describe "Author.author/2" do
    test "an empty or whitespace-only intent fails closed" do
      assert Author.author("") == {:error, :empty_intent}
      assert Author.author("   \n\t ") == {:error, :empty_intent}
    end

    test "a structurally clean draft returns {:ok, plan} and writes nothing without :out" do
      assert {:ok, %{plan: plan, path: nil}} =
               Author.author("ready issues CLI",
                 draft_opts: [drafter: StubDrafter, stub_plan: clean_plan()]
               )

      assert plan["goal"] == "Print the set of ready issues."
    end

    test "writes the drafted plan to :out and returns the path" do
      path = tmp_path()

      assert {:ok, %{path: ^path}} =
               Author.author("x",
                 out: path,
                 draft_opts: [drafter: StubDrafter, stub_plan: clean_plan()]
               )

      assert File.exists?(path)
      assert Jason.decode!(File.read!(path))["goal"] == "Print the set of ready issues."
      File.rm(path)
    end

    test "a draft with audit gaps returns {:needs_clarification, questions}" do
      assert {:needs_clarification, questions} =
               Author.author("x", draft_opts: [drafter: StubDrafter, stub_plan: gap_plan()])

      assert [%{id: "Q1", prompt: prompt} | _] = questions
      assert prompt =~ "REQ-002"
    end

    test "propagates a drafter error and writes no file" do
      path = tmp_path()

      assert {:error, :drafter_unavailable} =
               Author.author("x", out: path, draft_opts: [drafter: FailingDrafter])

      refute File.exists?(path)
    end
  end

  describe "mix conveyor.author" do
    setup do
      Mix.shell(Mix.Shell.Process)
      test_pid = self()
      Process.put(:conveyor_author_exit_fun, fn code -> send(test_pid, {:exit, code}) end)

      on_exit(fn ->
        Mix.shell(Mix.Shell.IO)
        Process.delete(:conveyor_author_draft_opts)
        Process.delete(:conveyor_author_exit_fun)
      end)

      :ok
    end

    test "drafts a clean plan, emits a JSON summary, and exits success" do
      path = tmp_path()
      Process.put(:conveyor_author_draft_opts, drafter: StubDrafter, stub_plan: clean_plan())

      Mix.Tasks.Conveyor.Author.run(["ready issues CLI", "--out", path])

      assert_received {:exit, code}
      assert code == ExitCodes.fetch!(:success)

      assert_received {:mix_shell, :info, [json]}
      summary = Jason.decode!(json)
      assert summary["status"] == "drafted"
      assert summary["out"] == path
      assert summary["requirement_count"] == 1

      File.rm(path)
    end

    test "surfaces operator questions and exits non-zero when the draft needs clarification" do
      Process.put(:conveyor_author_draft_opts, drafter: StubDrafter, stub_plan: gap_plan())

      Mix.Tasks.Conveyor.Author.run(["x", "--out", tmp_path()])

      assert_received {:exit, code}
      assert code == ExitCodes.fetch!(:deterministic_gate_failed)

      assert_received {:mix_shell, :info, [json]}
      decoded = Jason.decode!(json)
      assert decoded["status"] == "needs_clarification"
      assert [%{"id" => "Q1"} | _] = decoded["questions"]
    end
  end
end
