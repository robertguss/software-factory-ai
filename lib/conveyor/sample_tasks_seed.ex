defmodule Conveyor.SampleTasksSeed do
  @moduledoc """
  Seeds the Phase 1 sample tasks work graph.

  The seed is intentionally idempotent: mutable graph resources are updated in
  place, immutable resources are reused when their locked digests already match,
  and the first recorded base commit is preserved on later seed runs.
  """

  alias Conveyor.Factory
  alias Conveyor.Factory.AgentBrief
  alias Conveyor.Factory.ContractLock
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Project
  alias Conveyor.Factory.RunSpec
  alias Conveyor.Factory.Slice
  alias Conveyor.Factory.TestPack
  alias Conveyor.PlanContract
  alias Conveyor.PlanImport
  alias Conveyor.SampleTasksContract

  @sample_plan_path "samples/tasks_service/plan.md"

  defmodule Result do
    @moduledoc "Seeded sample graph resources."

    @type t :: %__MODULE__{
            project: struct(),
            plan: struct(),
            requirements: [struct()],
            human_decisions: [struct()],
            epic: struct(),
            slice: struct(),
            agent_brief: struct(),
            test_pack: struct(),
            contract_lock: struct(),
            run_spec: struct(),
            base_commit: String.t()
          }

    @enforce_keys [
      :project,
      :plan,
      :requirements,
      :human_decisions,
      :epic,
      :slice,
      :agent_brief,
      :test_pack,
      :contract_lock,
      :run_spec,
      :base_commit
    ]
    defstruct [
      :project,
      :plan,
      :requirements,
      :human_decisions,
      :epic,
      :slice,
      :agent_brief,
      :test_pack,
      :contract_lock,
      :run_spec,
      :base_commit
    ]
  end

  @spec seed!(keyword()) :: Result.t()
  def seed!(opts \\ []) do
    repo_root = Keyword.get_lazy(opts, :repo_root, &repo_root/0)
    plan_path = Keyword.get(opts, :plan_path, Path.join(repo_root, @sample_plan_path))
    locked_at = Keyword.get_lazy(opts, :locked_at, fn -> DateTime.utc_now(:microsecond) end)
    locked_by = Keyword.get(opts, :locked_by, "human-test-architect")

    {:ok, contract_result} = PlanContract.load(plan_path)

    project = upsert_project!(repo_root, contract_result)
    plan = upsert_plan!(project, contract_result)
    import_result = PlanImport.import_requirements_and_decisions!(plan, contract_result)
    epic = upsert_epic!(plan, contract_result)
    slice = upsert_slice!(epic, contract_result)
    contract_opts = [repo_root: repo_root, locked_at: locked_at, locked_by: locked_by]
    agent_brief = get_or_create_agent_brief!(slice, contract_opts)
    test_pack = get_or_create_test_pack!(slice, contract_opts)
    contract_lock = get_or_create_contract_lock!(slice, agent_brief, contract_opts)
    base_commit = Keyword.get_lazy(opts, :base_commit, fn -> base_commit!(repo_root) end)
    run_spec = get_or_create_run_spec!(slice, contract_lock, test_pack, base_commit)

    %Result{
      project: project,
      plan: plan,
      requirements: import_result.requirements,
      human_decisions: import_result.human_decisions,
      epic: epic,
      slice: slice,
      agent_brief: agent_brief,
      test_pack: test_pack,
      contract_lock: contract_lock,
      run_spec: run_spec,
      base_commit: run_spec.base_commit
    }
  end

  defp upsert_project!(repo_root, %PlanContract.Result{
         contract: contract,
         source_path: source_path
       }) do
    project_contract = Map.fetch!(contract, "project")
    sample_root = source_path |> Path.dirname() |> Path.expand()

    attrs = %{
      name: Map.fetch!(project_contract, "key"),
      local_path: sample_root,
      default_branch: Map.fetch!(project_contract, "base_ref"),
      command_specs:
        Ash.UUID.generate()
        |> SampleTasksContract.agent_brief_attrs!(
          [repo_root: repo_root] ++ contract_opts_for_project()
        )
        |> Map.fetch!(:verification_commands),
      default_autonomy_level: 1
    }

    case find_one(Project, &(&1.local_path == sample_root)) do
      nil -> Ash.create!(Project, attrs, domain: Factory)
      project -> Ash.update!(project, attrs, domain: Factory)
    end
  end

  defp upsert_plan!(project, %PlanContract.Result{} = contract_result) do
    attrs = %{
      project_id: project.id,
      title: "#{contract_result.contract["project"]["key"]} plan",
      intent: Map.fetch!(contract_result.contract, "goal"),
      source_document: contract_result.source_path,
      normalized_contract: contract_result.contract,
      contract_sha256: contract_result.contract_sha256
    }

    case find_one(
           Plan,
           &(&1.project_id == project.id and &1.contract_sha256 == contract_result.contract_sha256)
         ) do
      nil -> Ash.create!(Plan, attrs, domain: Factory)
      plan -> Ash.update!(plan, attrs, domain: Factory)
    end
  end

  defp upsert_epic!(plan, %PlanContract.Result{contract: contract}) do
    attrs = %{
      plan_id: plan.id,
      title: "Sample tasks completion",
      description: Map.fetch!(contract, "goal"),
      risk: risk(contract),
      status: :open
    }

    case find_one(Epic, &(&1.plan_id == plan.id and &1.title == attrs.title)) do
      nil -> Ash.create!(Epic, attrs, domain: Factory)
      epic -> Ash.update!(epic, attrs, domain: Factory)
    end
  end

  defp upsert_slice!(epic, %PlanContract.Result{contract: contract}) do
    slice_contract = first_slice!(contract)

    attrs = %{
      epic_id: epic.id,
      title: Map.fetch!(slice_contract, "title"),
      position: 1,
      risk: risk(contract),
      autonomy_level: Map.fetch!(slice_contract, "autonomy_ceiling"),
      source_refs: Map.fetch!(slice_contract, "requirement_refs"),
      likely_files: Map.fetch!(slice_contract, "likely_files"),
      conflict_domains: Map.fetch!(slice_contract, "conflict_domains")
    }

    case find_one(Slice, &(&1.epic_id == epic.id and &1.position == 1)) do
      nil -> Ash.create!(Slice, attrs, domain: Factory)
      slice -> Ash.update!(slice, attrs, domain: Factory)
    end
  end

  defp get_or_create_agent_brief!(slice, opts) do
    attrs = SampleTasksContract.agent_brief_attrs!(slice.id, opts)

    case find_one(AgentBrief, &(&1.slice_id == slice.id and &1.version == 1)) do
      nil ->
        Ash.create!(AgentBrief, attrs, domain: Factory)

      agent_brief ->
        agent_brief
    end
  end

  defp get_or_create_test_pack!(slice, opts) do
    attrs = SampleTasksContract.test_pack_attrs!(slice.id, opts)

    case find_one(TestPack, &(&1.slice_id == slice.id and &1.version == 1)) do
      nil ->
        Ash.create!(TestPack, attrs, domain: Factory)

      test_pack ->
        ensure_digest!("TestPack", test_pack.test_pack_sha256, attrs.test_pack_sha256)
        test_pack
    end
  end

  defp get_or_create_contract_lock!(slice, agent_brief, opts) do
    attrs = SampleTasksContract.contract_lock_attrs!(slice.id, agent_brief.id, opts)

    case find_one(
           ContractLock,
           &(&1.slice_id == slice.id and &1.agent_brief_id == agent_brief.id)
         ) do
      nil ->
        Ash.create!(ContractLock, attrs, domain: Factory)

      contract_lock ->
        ensure_digest!(
          "ContractLock.test_pack",
          contract_lock.test_pack_sha256,
          attrs.test_pack_sha256
        )

        contract_lock
    end
  end

  defp get_or_create_run_spec!(slice, contract_lock, test_pack, base_commit) do
    case find_one(RunSpec, &(&1.slice_id == slice.id and &1.attempt_no == 1)) do
      nil ->
        attrs = run_spec_attrs(slice, contract_lock, test_pack, base_commit)
        Ash.create!(RunSpec, attrs, domain: Factory)

      run_spec ->
        run_spec
    end
  end

  defp run_spec_attrs(slice, contract_lock, test_pack, base_commit) do
    contract_lock_sha256 = digest_value(contract_lock_payload(contract_lock))

    run_spec_seed = %{
      "slice_id" => slice.id,
      "attempt_no" => 1,
      "base_commit" => base_commit,
      "contract_lock_sha256" => contract_lock_sha256,
      "test_pack_sha256" => test_pack.test_pack_sha256
    }

    run_spec_sha256 = digest_value(run_spec_seed)
    station_plan = station_plan(run_spec_sha256)

    %{
      slice_id: slice.id,
      attempt_no: 1,
      run_spec_json_ref: "samples/tasks_service/.conveyor/run-specs/SLICE-001-attempt-1.json",
      run_spec_sha256: run_spec_sha256,
      base_commit: base_commit,
      contract_lock_sha256: contract_lock_sha256,
      prompt_template_version: "implementation-prompt@1",
      agent_profile_snapshot: %{"adapter" => "pi", "model" => "gpt-5"},
      policy_sha256: contract_lock.policy_sha256,
      diff_policy_sha256: diff_policy_sha256(slice),
      test_pack_sha256: test_pack.test_pack_sha256,
      station_plan: station_plan,
      station_plan_sha256: digest_value(station_plan),
      container_image_ref: "ghcr.io/conveyor/sample-python-runner:2026-06-01",
      container_image_digest:
        digest_value(%{"image_ref" => "ghcr.io/conveyor/sample-python-runner:2026-06-01"}),
      sandbox_profile: "verify",
      budget_sha256: digest_value(%{"profile" => "sample", "timeout_ms" => 120_000}),
      code_quality_profile: "standard",
      canary_suite_version: "canary@1"
    }
  end

  defp station_plan(run_spec_sha256) do
    %{
      "schema_version" => "conveyor.station_plan@1",
      "stations" => [
        %{
          "key" => "seed",
          "kind" => "seed",
          "input" => %{"run_spec_sha256" => run_spec_sha256, "artifact_refs" => []},
          "output" => %{"run_spec_sha256" => run_spec_sha256, "artifact_refs" => []}
        }
      ]
    }
  end

  defp contract_lock_payload(contract_lock) do
    %{
      "plan_contract_sha256" => contract_lock.plan_contract_sha256,
      "brief_sha256" => contract_lock.brief_sha256,
      "acceptance_criteria_sha256" => contract_lock.acceptance_criteria_sha256,
      "required_tests_sha256" => contract_lock.required_tests_sha256,
      "test_pack_sha256" => contract_lock.test_pack_sha256,
      "verification_commands_sha256" => contract_lock.verification_commands_sha256,
      "agents_md_sha256" => contract_lock.agents_md_sha256,
      "policy_sha256" => contract_lock.policy_sha256,
      "protected_path_globs" => contract_lock.protected_path_globs
    }
  end

  defp diff_policy_sha256(slice) do
    digest_value(%{
      "allowed_path_globs" => slice.likely_files,
      "protected_path_globs" => SampleTasksContract.protected_path_globs()
    })
  end

  defp contract_opts_for_project do
    [locked_at: ~U[2026-06-18 00:00:00Z], locked_by: "human-test-architect"]
  end

  defp first_slice!(contract) do
    contract
    |> Map.fetch!("slices")
    |> Enum.find(&(Map.fetch!(&1, "key") == "SLICE-001"))
  end

  defp risk(contract) do
    risks =
      contract
      |> Map.fetch!("requirements")
      |> Enum.map(&Map.fetch!(&1, "risk"))

    cond do
      "high" in risks -> "high"
      "medium" in risks -> "medium"
      true -> "low"
    end
  end

  defp find_one(resource, predicate) do
    resource
    |> Ash.read!(domain: Factory)
    |> Enum.find(predicate)
  end

  defp ensure_digest!(resource, existing, expected) do
    if existing != expected do
      raise ArgumentError,
            "#{resource} digest mismatch; existing #{existing}, expected #{expected}"
    end
  end

  defp base_commit!(repo_root) do
    case git_fun().(repo_root, ["rev-parse", "HEAD"]) do
      {output, 0} -> String.trim(output)
      {output, status} -> raise "git rev-parse HEAD failed with #{status}: #{output}"
    end
  end

  defp git_fun do
    Process.get(:conveyor_seed_sample_git_fun, fn repo_root, args ->
      System.cmd("git", ["-C", repo_root | args], stderr_to_stdout: true)
    end)
  end

  defp digest_value(value), do: value |> canonical_json() |> sha256()

  defp canonical_json(value) when is_map(value) do
    body =
      value
      |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
      |> Enum.map(fn {key, nested} ->
        Jason.encode!(to_string(key)) <> ":" <> canonical_json(nested)
      end)
      |> Enum.join(",")

    "{" <> body <> "}"
  end

  defp canonical_json(value) when is_list(value) do
    "[" <> Enum.map_join(value, ",", &canonical_json/1) <> "]"
  end

  defp canonical_json(value), do: Jason.encode!(value)

  defp sha256(content) do
    "sha256:" <> Base.encode16(:crypto.hash(:sha256, content), case: :lower)
  end

  defp repo_root do
    __DIR__
    |> Path.join("../..")
    |> Path.expand()
  end
end
