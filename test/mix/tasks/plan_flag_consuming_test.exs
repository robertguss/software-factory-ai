defmodule Mix.Tasks.PlanFlagConsumingTest do
  @moduledoc """
  685n (mmxr.1 follow-up): CLI-level consuming tests for the 5 load-bearing config/CLI knobs the
  config-surface audit (docs/audits/config-surface-truth.md) found without dedicated coverage.
  Each asserts the operator's knob observably changes what the task produces — the load-bearing
  half of the never-lie contract. The scout/config impl these exercise is prior-authored.
  """
  use Conveyor.DataCase, async: false

  import ExUnit.CaptureIO

  alias Conveyor.AgentsMd.Linter
  alias Conveyor.Factory
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.Project

  defp tmp_dir!(label) do
    dir = Path.join(System.tmp_dir!(), "plan-flag-#{label}-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end

  @exit_seams [:conveyor_task_exit_fun, :conveyor_plan_prepare_exit_fun]

  defp run_task!(task, args) do
    test_pid = self()
    for seam <- @exit_seams, do: Process.put(seam, fn code -> send(test_pid, {:exit, code}) end)
    on_exit(fn -> for seam <- @exit_seams, do: Process.delete(seam) end)

    capture_io(fn ->
      Mix.Task.reenable(task)
      Mix.Task.run(task, args)
    end)
  end

  test "plan.create --epic-title and --project-name land on the created Epic and Project" do
    ws = tmp_dir!("create")

    run_task!("conveyor.plan.create", [
      "--workspace-path",
      ws,
      "--title",
      "Baseline Title",
      "--intent",
      "add a widget",
      "--epic-title",
      "Custom Epic Name",
      "--project-name",
      "Custom Project Name"
    ])

    project = Project |> Ash.read!(domain: Factory) |> Enum.find(&(&1.local_path == ws))
    assert project, "expected a project created at the workspace path"

    # --project-name is load-bearing: the Project carries it, not the "conveyor-plan" default
    assert project.name == "Custom Project Name"

    plan_ids = plan_ids_for(project)
    epic = Epic |> Ash.read!(domain: Factory) |> Enum.find(&(&1.plan_id in plan_ids))
    assert epic, "expected an epic under the created plan"
    # --epic-title is load-bearing: the Epic carries it (not the plan --title fallback)
    assert epic.title == "Custom Epic Name"
  end

  test "plan.create --project-name defaults observably when omitted (contrast)" do
    ws = tmp_dir!("create-default")

    run_task!("conveyor.plan.create", [
      "--workspace-path",
      ws,
      "--title",
      "T",
      "--intent",
      "do things"
    ])

    project = Project |> Ash.read!(domain: Factory) |> Enum.find(&(&1.local_path == ws))
    assert project.name == "conveyor-plan"
  end

  test "plan.import --workspace-path sets the imported Project's local_path" do
    doc = Path.expand("../../../docs/schemas/examples/conveyor.plan.valid.json", __DIR__)
    ws = tmp_dir!("import")

    run_task!("conveyor.plan.import", [doc, "--workspace-path", ws])

    assert Project |> Ash.read!(domain: Factory) |> Enum.any?(&(&1.local_path == ws)),
           "expected the imported project to carry the --workspace-path"
  end

  test "plan_prepare requires --no-agents to run; without it, it refuses (the flag is load-bearing)" do
    doc = Path.expand("../../../docs/schemas/examples/conveyor.plan.valid.json", __DIR__)

    # with --no-agents: the task runs and prepares (emits output, exits)
    out = run_task!("conveyor.plan_prepare", [doc, "--no-agents", "--format", "json"])
    assert out != ""
    assert_received {:exit, _code}

    # without --no-agents: the guard fails closed with usage (does not silently proceed)
    assert_raise Mix.Error, ~r/usage: mix conveyor\.plan_prepare/, fn ->
      Mix.Task.reenable("conveyor.plan_prepare")
      Mix.Task.run("conveyor.plan_prepare", [doc, "--format", "json"])
    end
  end

  test "config policies_dir determines which policy denylist the AGENTS.md linter enforces" do
    project_path = tmp_dir!("policies")
    scaffold_project!(project_path)
    # A Forbidden Actions section WITHOUT the "denied commands" catch-all, so the linter runs the
    # per-entry denylist check (the catch-all short-circuits it). Same AGENTS.md for both loads.
    File.write!(
      Path.join(project_path, "AGENTS.md"),
      "# Forbidden Actions\n\nDo not merge or deploy without approval.\n"
    )

    # policies_dir -> an empty dir: nothing is loaded, so no denylist finding
    File.mkdir_p!(Path.join(project_path, "empty_policies"))
    redirect_policies_dir!(project_path, "empty_policies")
    assert {:ok, base} = Linter.lint(project_path)
    refute :missing_policy_denylist in finding_codes(base)

    # policies_dir -> a dir carrying a denylist entry: the linter now enforces THAT entry
    custom = Path.join(project_path, "custom_policies")
    File.mkdir_p!(custom)

    File.write!(
      Path.join(custom, "extra.toml"),
      "[policy]\ndenylist = [\"conveyor685nmarker\"]\n"
    )

    redirect_policies_dir!(project_path, "custom_policies")

    # load-bearing: the finding names the custom dir's entry — only reachable if policies_dir was
    # read. If the dir were hardcoded, the marker (which lives only in custom_policies) never shows.
    assert {:ok, redirected} = Linter.lint(project_path)

    assert Enum.any?(redirected.findings, fn f ->
             f.code == :missing_policy_denylist and f.message =~ "conveyor685nmarker"
           end)
  end

  defp scaffold_project!(project_path) do
    File.mkdir_p!(Path.join(project_path, ".conveyor/policies"))

    File.cp!(
      "priv/conveyor/templates/config.toml",
      Path.join(project_path, ".conveyor/config.toml")
    )

    for policy <- ~w(implement verify) do
      File.cp!(
        "priv/conveyor/templates/policies/#{policy}.toml",
        Path.join(project_path, ".conveyor/policies/#{policy}.toml")
      )
    end
  end

  defp redirect_policies_dir!(project_path, rel) do
    config_path = Path.join(project_path, ".conveyor/config.toml")

    config_path
    |> File.read!()
    |> String.replace(~r/policies_dir = "[^"]*"/, ~s(policies_dir = "#{rel}"))
    |> then(&File.write!(config_path, &1))
  end

  defp finding_codes(result), do: Enum.map(result.findings, & &1.code)

  defp plan_ids_for(project) do
    Conveyor.Factory.Plan
    |> Ash.read!(domain: Factory)
    |> Enum.filter(&(&1.project_id == project.id))
    |> Enum.map(& &1.id)
  end
end
