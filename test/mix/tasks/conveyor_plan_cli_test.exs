defmodule Conveyor.Mix.Tasks.ConveyorPlanCliTest do
  @moduledoc """
  Coverage for the DB-native plan-authoring CLI front doors (F2): `conveyor.plan.import`,
  `conveyor.plan.create`, and `conveyor.epic.create`. These let an operator (or external AI) go
  from nothing to a runnable plan graph entirely through `mix conveyor.*`, replacing the dogfood's
  hand-written Ash seed script.
  """
  use Conveyor.DataCase, async: false

  import ExUnit.CaptureIO

  alias Conveyor.CLI.ExitCodes
  alias Conveyor.Factory
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Project
  alias Conveyor.Factory.Slice
  alias Conveyor.Factory.TaskDependency
  alias Conveyor.TaskGraph

  setup do
    test_pid = self()
    Process.put(:conveyor_task_exit_fun, fn code -> send(test_pid, {:exit_code, code}) end)
    on_exit(fn -> Process.delete(:conveyor_task_exit_fun) end)
    :ok
  end

  describe "conveyor.plan.import" do
    test "imports the real beads_insight sample into DB rows" do
      result = json(Mix.Tasks.Conveyor.Plan.Import, ["samples/beads_insight/conveyor.plan.yml"])

      assert result["slice_count"] == 7
      assert result["project_id"]
      assert result["plan_id"]
      assert result["epic_id"]
      assert result["contract_sha256"] =~ ~r/^sha256:/

      assert length(Ash.read!(Slice, domain: Factory)) == 7
    end

    test "materializes declared dependency edges" do
      doc = write_plan_doc!(contract_with_edges([%{"from" => "SLICE-001", "to" => "SLICE-002"}]))

      result = json(Mix.Tasks.Conveyor.Plan.Import, [doc])

      assert result["slice_count"] == 2
      assert [_edge] = Ash.read!(TaskDependency, domain: Factory)
    end

    test "a cyclic work_dependencies graph exits non-zero and persists nothing" do
      doc =
        write_plan_doc!(
          contract_with_edges([
            %{"from" => "SLICE-001", "to" => "SLICE-002"},
            %{"from" => "SLICE-002", "to" => "SLICE-001"}
          ])
        )

      capture_io(:stderr, fn -> Mix.Tasks.Conveyor.Plan.Import.run([doc]) end)

      assert_received {:exit_code, code}
      assert code == ExitCodes.fetch!(:malformed_artifact_or_schema_failure)
      assert Ash.read!(Plan, domain: Factory) == []
    end

    test "a missing path exits non-zero without crashing" do
      capture_io(:stderr, fn -> Mix.Tasks.Conveyor.Plan.Import.run(["does/not/exist.json"]) end)

      assert_received {:exit_code, code}
      assert code == ExitCodes.fetch!(:malformed_artifact_or_schema_failure)
    end

    test "a schema-valid but unsupported edge kind exits non-zero and persists nothing" do
      # `integration_order` is allowed by the JSON schema but unsupported by `TaskDependency` and
      # deferred by this plan; the import must reject it before writing any row, not half-import.
      doc =
        write_plan_doc!(
          Map.put(base_contract(), "work_dependencies", [
            %{"from" => "SLICE-001", "to" => "SLICE-002", "kind" => "integration_order"}
          ])
        )

      capture_io(:stderr, fn -> Mix.Tasks.Conveyor.Plan.Import.run([doc]) end)

      assert_received {:exit_code, code}
      assert code == ExitCodes.fetch!(:plan_or_readiness_blocked)
      assert Ash.read!(Plan, domain: Factory) == []
    end

    test "no plan-doc argument raises a usage error" do
      assert_raise Mix.Error, fn -> Mix.Tasks.Conveyor.Plan.Import.run([]) end
    end
  end

  describe "conveyor.plan.create" do
    test "creates a runnable Project + Plan + Epic shell carrying verification commands" do
      result =
        json(Mix.Tasks.Conveyor.Plan.Create, [
          "--workspace-path",
          "/tmp/cli-ws",
          "--title",
          "Insight CLI",
          "--intent",
          "Build the read-only insight CLI."
        ])

      assert result["project_id"]
      assert result["plan_id"]
      assert result["epic_id"]
      assert result["contract_sha256"] =~ ~r/^sha256:/

      plan = Ash.get!(Plan, result["plan_id"], domain: Factory)

      # A freshly-created shell is a `:draft` so the first `task.lock` compiles its contract from
      # the authored rows before freezing it (the draft -> handoff_ready lifecycle).
      assert plan.status == :draft

      assert plan.normalized_contract["verification_commands"] == [
               %{"key" => "pytest", "argv" => ["pytest", "-q"], "profile" => "verify"}
             ]
    end

    test "repeatable --verification-command overrides the pytest default" do
      result =
        json(Mix.Tasks.Conveyor.Plan.Create, [
          "--workspace-path",
          "/tmp/cli-ws-2",
          "--title",
          "T",
          "--intent",
          "I",
          "--verification-command",
          "mix test",
          "--verification-command",
          "mix credo --strict"
        ])

      plan = Ash.get!(Plan, result["plan_id"], domain: Factory)

      assert plan.normalized_contract["verification_commands"] == [
               %{"key" => "mix", "argv" => ["mix", "test"], "profile" => "verify"},
               %{"key" => "mix", "argv" => ["mix", "credo", "--strict"], "profile" => "verify"}
             ]
    end

    test "reuses the Project across repeated calls on the same workspace path" do
      first =
        json(Mix.Tasks.Conveyor.Plan.Create, [
          "--workspace-path",
          "/tmp/shared-ws",
          "--title",
          "One",
          "--intent",
          "First plan."
        ])

      second =
        json(Mix.Tasks.Conveyor.Plan.Create, [
          "--workspace-path",
          "/tmp/shared-ws",
          "--title",
          "Two",
          "--intent",
          "Second plan."
        ])

      assert first["project_id"] == second["project_id"]
      assert first["plan_id"] != second["plan_id"]
      assert length(Ash.read!(Project, domain: Factory)) == 1
    end

    test "the created shell is immediately authorable via task.create" do
      created =
        json(Mix.Tasks.Conveyor.Plan.Create, [
          "--workspace-path",
          "/tmp/authorable-ws",
          "--title",
          "Authorable",
          "--intent",
          "Author slices."
        ])

      task =
        json(Mix.Tasks.Conveyor.Task.Create, [
          "--epic",
          created["epic_id"],
          "--title",
          "First slice"
        ])

      assert task["stable_key"] == "SLICE-001"
    end

    test "a missing required flag raises a usage error" do
      assert_raise Mix.Error, fn ->
        Mix.Tasks.Conveyor.Plan.Create.run(["--title", "T", "--intent", "I"])
      end
    end

    test "the created shell locks and approves end-to-end (R8: runnable, no Ash seed)" do
      created =
        json(Mix.Tasks.Conveyor.Plan.Create, [
          "--workspace-path",
          "/tmp/runnable-ws",
          "--title",
          "Runnable",
          "--intent",
          "Author and run.",
          # A non-pytest verifier (the real dogfood target is this Elixir repo) must survive lock.
          "--verification-command",
          "mix test"
        ])

      # Author a gate-ready slice into the shell (the authoring an operator does after `plan.create`).
      task =
        TaskGraph.create_task(%{
          epic_id: created["epic_id"],
          title: "Loader",
          source_refs: ["REQ-001"],
          likely_files: ["lib/loader.ex"]
        })

      TaskGraph.set_acceptance(task.id, [
        %{
          "id" => "AC-001",
          "text" => "Loading the fixture corpus yields stable issue counts across reloads.",
          "requirement_refs" => ["REQ-001"],
          "required_test_refs" => ["tests/test_loader.py::test_counts"],
          "falsifying_conditions" => [
            %{
              "acceptance_criterion_id" => "AC-001",
              "condition" => "counts change when the same corpus is reloaded",
              "required_test_refs" => ["tests/test_loader.py::test_counts"]
            }
          ]
        }
      ])

      locked =
        json(Mix.Tasks.Conveyor.Task.Lock, ["--epic", created["epic_id"], "--key", "SLICE-001"])

      assert locked["locked"] == true

      approved =
        json(Mix.Tasks.Conveyor.Task.Approve, ["--epic", created["epic_id"], "--key", "SLICE-001"])

      assert approved["state"] == "approved"

      # The first lock compiled the draft contract from rows and advanced the plan past draft —
      # proving the `:draft`-at-create decision keeps the shell genuinely lockable/runnable.
      plan = Ash.get!(Plan, created["plan_id"], domain: Factory)
      assert plan.status == :handoff_ready

      # The operator's custom verification command survives the lock-time contract recompile
      # (ContractBuilder preserves plan-level verification_commands), so it reaches the run path
      # instead of being silently replaced by the `pytest -q` default.
      assert plan.normalized_contract["verification_commands"] == [
               %{"key" => "mix", "argv" => ["mix", "test"], "profile" => "verify"}
             ]
    end
  end

  describe "conveyor.epic.create" do
    test "adds an epic to an existing plan and is authorable" do
      created =
        json(Mix.Tasks.Conveyor.Plan.Create, [
          "--workspace-path",
          "/tmp/epic-ws",
          "--title",
          "Has epics",
          "--intent",
          "Many epics."
        ])

      epic =
        json(Mix.Tasks.Conveyor.Epic.Create, [
          "--plan",
          created["plan_id"],
          "--title",
          "Second epic",
          "--description",
          "More slices."
        ])

      assert epic["plan_id"] == created["plan_id"]
      assert epic["epic_id"]
      assert epic["status"] == "open"

      # Distinct from the `plan.create` first epic, and it accepts `task.create`.
      assert epic["epic_id"] != created["epic_id"]

      task = json(Mix.Tasks.Conveyor.Task.Create, ["--epic", epic["epic_id"], "--title", "Slice"])
      assert task["stable_key"] == "SLICE-001"
    end

    test "an unknown --plan UUID exits non-zero without crashing" do
      capture_io(:stderr, fn ->
        Mix.Tasks.Conveyor.Epic.Create.run([
          "--plan",
          Ecto.UUID.generate(),
          "--title",
          "T",
          "--description",
          "D"
        ])
      end)

      assert_received {:exit_code, code}
      assert code == ExitCodes.fetch!(:plan_or_readiness_blocked)
    end

    test "a missing required flag raises a usage error" do
      assert_raise Mix.Error, fn ->
        Mix.Tasks.Conveyor.Epic.Create.run(["--title", "T", "--description", "D"])
      end
    end
  end

  # -- helpers ----------------------------------------------------------------

  # Run a verb, return its decoded stdout JSON (asserting stdout is valid JSON), and consume its
  # success exit so later error-path assertions see only the failing exit code.
  defp json(mod, args) do
    out = capture_io(fn -> mod.run(args) end) |> String.trim() |> Jason.decode!()
    assert_received {:exit_code, code}
    assert code == ExitCodes.fetch!(:success)
    out
  end

  defp write_plan_doc!(contract) do
    path =
      Path.join(System.tmp_dir!(), "conveyor-plan-cli-#{System.unique_integer([:positive])}.json")

    File.write!(path, Jason.encode!(contract))
    on_exit(fn -> File.rm(path) end)
    path
  end

  defp contract_with_edges(edges) do
    base_contract()
    |> Map.put("work_dependencies", Enum.map(edges, &Map.put(&1, "kind", "execution_hard")))
  end

  defp base_contract do
    %{
      "schema_version" => "conveyor.plan@1",
      "project" => %{"key" => "tmp-cli", "base_ref" => "main"},
      "goal" => "Temp plan for the plan CLI test.",
      "non_goals" => [],
      "requirements" => [
        %{"key" => "REQ-001", "text" => "r", "risk" => "low", "source_ref" => "p#r"}
      ],
      "acceptance_criteria" => [
        %{
          "key" => "AC-001",
          "text" => "a",
          "requirement_refs" => ["REQ-001"],
          "required_test_refs" => []
        }
      ],
      "verification_commands" => [
        %{"key" => "pytest", "argv" => ["pytest", "-q"], "profile" => "verify"}
      ],
      "decisions" => [],
      "slices" => [slice("SLICE-001", "First"), slice("SLICE-002", "Second")]
    }
  end

  defp slice(key, title) do
    %{
      "key" => key,
      "title" => title,
      "requirement_refs" => ["REQ-001"],
      "likely_files" => [],
      "conflict_domains" => [],
      "autonomy_ceiling" => "L1"
    }
  end
end
