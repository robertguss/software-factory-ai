defmodule Conveyor.PlanAuditEvalTest do
  use Conveyor.DataCase, async: false

  alias Conveyor.Factory
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Project
  alias Conveyor.PlanAuditor
  alias Conveyor.PlanAuditReport
  alias Conveyor.PlanContract
  alias Conveyor.PlanImport

  @fixture_dir Path.expand("../fixtures/plan_audit", __DIR__)

  @fixtures [
    {"good", "handoff_ready"},
    {"missing-ac", "blocked"},
    {"missing-test", "blocked"},
    {"untraceable", "blocked"},
    {"vague", "blocked"},
    {"contradictory", "blocked"},
    {"prose-only", "contract_error"}
  ]

  for {name, expected_decision} <- @fixtures do
    @name name
    @expected_decision expected_decision

    test "#{name} fixture matches plan_audit snapshot" do
      actual = run_fixture(@name)
      snapshot_path = snapshot_path(@name)

      unless File.exists?(snapshot_path) do
        flunk("missing snapshot #{snapshot_path}\n\n#{actual}")
      end

      expected = File.read!(snapshot_path)

      assert actual == expected
      assert actual =~ "Decision: #{@expected_decision}" or @expected_decision == "contract_error"
    end
  end

  defp run_fixture("prose-only") do
    path = Path.join(@fixture_dir, "prose-only.md")

    case PlanContract.load(path) do
      {:error, error} ->
        "Plan contract error: #{error.code}\n#{error.message}\n"

      {:ok, _result} ->
        raise "prose-only fixture unexpectedly loaded"
    end
  end

  defp run_fixture(name) do
    path = Path.join(@fixture_dir, "#{name}.json")
    {:ok, contract_result} = PlanContract.load(path)
    project = create_project!(contract_result)
    plan = create_plan!(project, contract_result)
    PlanImport.import_requirements_and_decisions!(plan, contract_result)

    contract_result
    |> maybe_add_orphan_slice!(plan)
    |> case do
      :ok ->
        plan
        |> PlanAuditor.audit_plan!()
        |> PlanAuditReport.format()
        |> Kernel.<>("\n")
    end
  end

  defp maybe_add_orphan_slice!(%PlanContract.Result{source_path: source_path}, plan) do
    if Path.basename(source_path) == "untraceable.json" do
      epic =
        Ash.create!(
          Conveyor.Factory.Epic,
          %{
            plan_id: plan.id,
            title: "Untraceable eval epic",
            description: "Eval-only orphan slice coverage."
          },
          domain: Factory
        )

      Ash.create!(
        Conveyor.Factory.Slice,
        %{
          epic_id: epic.id,
          title: "Unmapped work",
          position: 2,
          source_refs: [],
          likely_files: ["app/main.py"],
          conflict_domains: ["tasks_api"]
        },
        domain: Factory
      )
    end

    :ok
  end

  defp create_project!(%PlanContract.Result{contract: contract, source_path: source_path}) do
    project = Map.fetch!(contract, "project")

    Ash.create!(
      Project,
      %{
        name: "#{Map.fetch!(project, "key")}-#{System.unique_integer([:positive])}",
        local_path: Path.dirname(source_path),
        default_branch: Map.fetch!(project, "base_ref")
      },
      domain: Factory
    )
  end

  defp create_plan!(project, %PlanContract.Result{} = contract_result) do
    Ash.create!(
      Plan,
      %{
        project_id: project.id,
        title: "#{contract_result.contract["project"]["key"]} eval plan",
        intent: Map.fetch!(contract_result.contract, "goal"),
        source_document: contract_result.source_path,
        normalized_contract: contract_result.contract,
        contract_sha256: contract_result.contract_sha256
      },
      domain: Factory
    )
  end

  defp snapshot_path(name), do: Path.join(@fixture_dir, "snapshots/#{name}.txt")
end
