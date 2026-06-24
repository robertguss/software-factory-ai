defmodule Conveyor.Planning.RunSpecAssembler do
  @moduledoc """
  Builds the immutable RunSpec for one production width-1 slice attempt.
  """

  alias Conveyor.CanonicalJson
  alias Conveyor.ContractEvolution
  alias Conveyor.ContractForge.{ContractAuthor, FalsifierForge}
  alias Conveyor.Factory

  alias Conveyor.Factory.{
    AgentBrief,
    ContractLock,
    DiffPolicy,
    Epic,
    Plan,
    Project,
    RunSpec,
    Slice,
    TestPack
  }

  alias Conveyor.Planning.WorkGraphToStationPlan
  alias Conveyor.Readiness

  @doc """
  Assemble and persist a `RunSpec` for a single slice.

  Required opts:

    * `:work_graph` - the single-slice work graph to lower.

  Runtime opts such as `:workspace_path`, `:base_commit`, `:blob_root`,
  `:patch_ref`, `:plan_path`, and `:agent_adapter` override derived defaults.
  """
  @spec assemble!(Slice.t() | Ecto.UUID.t(), keyword()) :: RunSpec.t()
  def assemble!(slice_or_id, opts \\ [])

  def assemble!(%Slice{} = slice, opts) do
    work_graph = Keyword.fetch!(opts, :work_graph)
    context = context_for!(slice)

    contract =
      slice
      |> ensure_contract_ready!(context, work_graph, opts)
      |> Map.put(:diff_policy, ensure_diff_policy!(slice, opts))

    workspace_path = Keyword.get(opts, :workspace_path, context.project.local_path)
    base_commit = Keyword.get_lazy(opts, :base_commit, fn -> git_head!(workspace_path) end)
    attempt_no = Keyword.get(opts, :attempt_no, 1)
    blob_root = Keyword.get(opts, :blob_root, ".conveyor/blobs")

    run_spec_sha256 =
      Keyword.get_lazy(opts, :run_spec_sha256, fn ->
        run_spec_digest(slice, work_graph, base_commit, attempt_no)
      end)

    station_plan =
      work_graph
      |> WorkGraphToStationPlan.lower(run_spec_sha256)
      |> case do
        {:ok, plan} ->
          augment_station_plan(plan, workspace_path, base_commit, blob_root, contract, opts)

        {:error, reason} ->
          raise ArgumentError, "cannot assemble RunSpec: #{inspect(reason)}"
      end

    Ash.create!(
      RunSpec,
      run_spec_attrs(
        slice,
        context,
        base_commit,
        attempt_no,
        run_spec_sha256,
        station_plan,
        contract,
        opts
      ),
      domain: Factory
    )
  end

  def assemble!(slice_id, opts) when is_binary(slice_id) do
    slice_id
    |> get_by_id!(Slice)
    |> assemble!(opts)
  end

  @doc """
  Materialize and lock the contract for a single slice from its row, without building a full
  `RunSpec`.

  This is the public seam the DB-native `lock` step (`Conveyor.TaskGraph.lock_task`) delegates to
  (KTD3): it builds the assembler context and a one-slice `conveyor.work_graph@2` from the slice
  row, then runs the same deterministic, offline `materialize_contract!` the run path uses — so the
  run later finds an already-`:ready` contract and consumes it unchanged. The slice's plan must
  already carry a compiled `normalized_contract` (acceptance is read from it).

  Returns `%{agent_brief:, contract_lock:, test_pack:, falsifier_forge:}`.
  """
  def materialize_contract_for_slice!(%Slice{} = slice, opts \\ []) do
    materialize_contract!(slice, context_for!(slice), single_slice_work_graph(slice), opts)
  end

  defp single_slice_work_graph(%Slice{} = slice) do
    %{
      "schema_version" => "conveyor.work_graph@2",
      "slices" => [
        %{
          "stable_key" => slice.stable_key,
          "title" => slice.title,
          "requirement_refs" => slice.source_refs,
          "likely_files" => slice.likely_files,
          "conflict_domains" => slice.conflict_domains
        }
      ],
      "work_dependencies" => []
    }
  end

  defp augment_station_plan(plan, workspace_path, base_commit, blob_root, contract, opts) do
    patch_ref = Keyword.get(opts, :patch_ref)
    # Optional reference/test-only map of attempt_no (string) => patch path, so a
    # retry can apply a DIFFERENT canned patch than the first attempt. Rides in the
    # implement-station input; `RunSpecForge.forge_retry!` copies it forward verbatim
    # (the map is stable — only the attempt_no lookup key changes). Production Codex
    # ignores it.
    patch_refs_by_attempt = Keyword.get(opts, :patch_refs_by_attempt)
    plan_path = Keyword.get(opts, :plan_path, Path.join(workspace_path, "conveyor.plan.yml"))
    adapter = Keyword.get(opts, :agent_adapter)

    stations =
      Enum.map(plan["stations"], fn station ->
        extra =
          case station["key"] do
            "context_scout" ->
              %{}

            "baseline_health" ->
              %{"blob_root" => blob_root}

            "acceptance_calibration" ->
              # M4-A4: the base workspace + base_commit let the station run the locked
              # acceptance commands FOR REAL at base — in an ISOLATED git worktree, never
              # the live tree — so calibration is `:valid` only when those tests genuinely
              # fail at base. Falls back to the default runner when absent.
              %{
                "workspace_path" => workspace_path,
                "base_commit" => base_commit,
                "blob_root" => blob_root
              }

            "implement" ->
              %{
                "workspace_path" => workspace_path,
                "base_commit" => base_commit,
                "blob_root" => blob_root
              }
              |> maybe_put("patch_ref", patch_ref)
              |> maybe_put("patch_refs_by_attempt", patch_refs_by_attempt)
              |> maybe_put("adapter", module_name(adapter))

            "verify" ->
              %{
                "workspace_path" => workspace_path,
                "plan_path" => plan_path,
                "test_refs" => contract.test_pack.required_test_refs
              }

            "record_evidence" ->
              %{"blob_root" => blob_root}

            _ ->
              %{}
          end

        Map.update!(station, "input", &Map.merge(&1, extra))
      end)

    plan
    |> Map.put("falsifier_forge", contract.falsifier_forge)
    |> Map.put("stations", stations)
  end

  defp run_spec_attrs(
         slice,
         context,
         base_commit,
         attempt_no,
         run_spec_sha256,
         station_plan,
         contract,
         opts
       ) do
    contract_lock = contract.contract_lock
    test_pack = contract.test_pack

    %{
      slice_id: slice.id,
      attempt_no: attempt_no,
      run_spec_json_ref:
        Keyword.get(
          opts,
          :run_spec_json_ref,
          "artifacts/run-specs/#{slice.id}-attempt-#{attempt_no}.json"
        ),
      run_spec_sha256: run_spec_sha256,
      base_commit: base_commit,
      contract_lock_sha256:
        Keyword.get_lazy(opts, :contract_lock_sha256, fn ->
          contract_lock_sha256(contract_lock, context.plan)
        end),
      prompt_template_version:
        Keyword.get(opts, :prompt_template_version, "implementation-prompt@1"),
      agent_profile_snapshot:
        Keyword.get(opts, :agent_profile_snapshot, %{
          "adapter" =>
            module_name(Keyword.get(opts, :agent_adapter)) || "Conveyor.AgentRunner.Codex"
        }),
      policy_sha256:
        Keyword.get_lazy(opts, :policy_sha256, fn -> policy_sha256(contract_lock) end),
      diff_policy_sha256:
        Keyword.get_lazy(opts, :diff_policy_sha256, fn ->
          diff_policy_sha256(contract.diff_policy)
        end),
      test_pack_sha256:
        Keyword.get_lazy(opts, :test_pack_sha256, fn -> test_pack_sha256(test_pack) end),
      station_plan: station_plan,
      station_plan_sha256: CanonicalJson.digest(station_plan),
      container_image_ref:
        Keyword.get(
          opts,
          :container_image_ref,
          "ghcr.io/conveyor/sample-python-runner:2026-06-17"
        ),
      container_image_digest: Keyword.get(opts, :container_image_digest, digest("image")),
      sandbox_profile: Keyword.get(opts, :sandbox_profile, "verify"),
      budget_sha256: Keyword.get(opts, :budget_sha256, digest("budget")),
      code_quality_profile:
        Keyword.get(opts, :code_quality_profile, context.project.code_quality_profile),
      canary_suite_version: Keyword.get(opts, :canary_suite_version, "canary@1")
    }
  end

  defp context_for!(slice) do
    epic = get_by_id!(slice.epic_id, Epic)
    plan = get_by_id!(epic.plan_id, Plan)
    project = get_by_id!(plan.project_id, Project)
    %{epic: epic, plan: plan, project: project}
  end

  defp ensure_contract_ready!(slice, context, work_graph, opts) do
    if Keyword.get(opts, :materialize_contract?, true) do
      ensure_materialized_contract!(slice, context, work_graph, opts)
      slice |> check_readiness(opts) |> ready_contract!(slice, context, work_graph, opts)
    else
      latest_contract!(slice.id)
    end
  end

  defp ensure_materialized_contract!(slice, context, work_graph, opts) do
    case latest_contract(slice.id) do
      %{agent_brief: %AgentBrief{}, contract_lock: %ContractLock{}, test_pack: %TestPack{}} ->
        :ok

      _missing ->
        materialize_contract!(slice, context, work_graph, opts)
    end
  end

  defp ensure_diff_policy!(slice, opts) do
    case Keyword.get(opts, :diff_policy) do
      %DiffPolicy{} = diff_policy ->
        diff_policy

      nil ->
        latest_diff_policy(slice) || create_default_diff_policy!(slice)
    end
  end

  defp latest_diff_policy(%Slice{diff_policy_id: diff_policy_id})
       when is_binary(diff_policy_id) do
    get_by_id!(diff_policy_id, DiffPolicy)
  end

  defp latest_diff_policy(%Slice{id: slice_id}) do
    DiffPolicy
    |> Ash.read!(domain: Factory)
    |> Enum.filter(&(&1.slice_id == slice_id))
    |> List.first()
  end

  defp create_default_diff_policy!(%Slice{} = slice) do
    diff_policy =
      Ash.create!(
        DiffPolicy,
        %{
          slice_id: slice.id,
          allowed_path_globs: slice.likely_files,
          protected_path_globs: locked_test_paths(slice),
          max_files_changed: max(length(slice.likely_files), 1),
          dependency_changes_allowed: false,
          migrations_allowed: false,
          generated_files_allowed: false,
          public_api_changes_allowed: false,
          notes: "Generated from slice likely_files during RunSpec assembly."
        },
        domain: Factory
      )

    Ash.update!(slice, %{diff_policy_id: diff_policy.id}, domain: Factory)
    diff_policy
  end

  defp ready_contract!(%Readiness.Result{status: :ready}, slice, _context, _work_graph, _opts),
    do: latest_contract!(slice.id)

  defp ready_contract!(%Readiness.Result{}, slice, context, work_graph, opts) do
    refreshed = materialize_contract!(slice, context, work_graph, opts)
    slice |> check_readiness(opts) |> require_ready!(slice, refreshed)
  end

  defp require_ready!(%Readiness.Result{status: :ready}, _slice, contract), do: contract

  defp require_ready!(%Readiness.Result{} = still_blocked, slice, _contract) do
    raise ArgumentError, "slice #{slice.id} is not ready: #{inspect(still_blocked.findings)}"
  end

  defp check_readiness(slice, opts) do
    Readiness.check(slice, actor: Keyword.get(opts, :actor, "run-spec-assembler"))
  end

  defp materialize_contract!(slice, context, work_graph, opts) do
    spec = contract_spec(slice, context, work_graph, opts)
    now = Keyword.get_lazy(opts, :locked_at, fn -> DateTime.utc_now(:microsecond) end)
    locked_by = Keyword.get(opts, :locked_by, "run-spec-assembler")
    version = next_contract_version(slice.id)
    author_result = ContractAuthor.materialize(contract_author_input(slice, spec))

    unless author_result.status == :passed do
      raise ArgumentError,
            "contract author blocked slice #{slice.id}: #{inspect(author_result.findings)}"
    end

    agent_brief =
      Ash.create!(
        AgentBrief,
        agent_brief_attrs(slice, spec, author_result.contract, version, now, locked_by),
        domain: Factory
      )

    test_pack =
      Ash.create!(
        TestPack,
        test_pack_attrs(slice, context, spec, version, now, locked_by),
        domain: Factory
      )

    contract_lock =
      Ash.create!(
        ContractLock,
        contract_lock_attrs(slice, context, spec, agent_brief, test_pack, now, locked_by),
        domain: Factory
      )

    %{
      agent_brief: agent_brief,
      contract_lock: contract_lock,
      test_pack: test_pack,
      falsifier_forge:
        FalsifierForge.run!(spec.acceptance_criteria, author_result.falsifier_seeds)
    }
  end

  defp contract_spec(slice, context, work_graph, opts) do
    work_slice = single_work_slice!(work_graph)

    stable_key =
      fetch(work_slice, "stable_key") || fetch(work_slice, "key") || "slice-#{slice.position}"

    requirement_refs = non_empty(string_list(work_slice, "requirement_refs"), slice.source_refs)
    likely_files = non_empty(string_list(work_slice, "likely_files"), slice.likely_files)

    conflict_domains =
      non_empty(string_list(work_slice, "conflict_domains"), slice.conflict_domains)

    acceptance_criteria =
      acceptance_criteria(work_slice, context.plan.normalized_contract, requirement_refs)

    required_tests = required_tests(acceptance_criteria)
    verification_commands = command_specs(context.plan.normalized_contract, context.project)

    out_of_scope =
      non_empty(string_list(context.plan.normalized_contract, "non_goals"), [
        "No unrelated changes."
      ])

    %{
      stable_key: stable_key,
      requirement_refs: requirement_refs,
      likely_files: likely_files,
      conflict_domains: conflict_domains,
      acceptance_criteria: acceptance_criteria,
      required_tests: required_tests,
      verification_commands: verification_commands,
      out_of_scope: out_of_scope,
      risk: Keyword.get(opts, :risk, slice.risk || "medium"),
      current_behavior:
        Keyword.get(
          opts,
          :current_behavior,
          "The base project contains the current #{context.plan.title} behavior."
        ),
      desired_behavior:
        Keyword.get(
          opts,
          :desired_behavior,
          "#{slice.title} satisfies #{Enum.map_join(acceptance_criteria, ", ", & &1["id"])}."
        )
    }
  end

  defp contract_author_input(slice, spec) do
    %{
      "slice_id" => spec.stable_key,
      "role_view" => %{
        "claims" => Enum.map(spec.acceptance_criteria, & &1["id"]),
        "interfaces" => spec.likely_files,
        "constraints" => spec.conflict_domains,
        "bounded_context" => spec.requirement_refs
      },
      "behavior" => %{
        "current" => spec.current_behavior,
        "desired" => spec.desired_behavior
      },
      "archetype" => "custom",
      "change_class" => "custom",
      "acceptance_criteria" =>
        Enum.map(spec.acceptance_criteria, fn criterion ->
          criterion
          |> Map.put_new("machine_checkable", true)
          |> Map.put_new("verification_stage", "unit")
        end),
      "authorized_scope" => %{
        "description" => "#{slice.title} implementation files and locked tests only.",
        "protected_paths" => protected_path_globs(spec)
      },
      "rollout" => %{"environment" => "local-test", "intent" => "first-light width-1 run"},
      "recovery" => %{"intent" => "revert the slice patch and preserve locked tests"},
      "out_of_scope" => spec.out_of_scope
    }
  end

  defp agent_brief_attrs(slice, spec, contract, version, now, locked_by) do
    %{
      slice_id: slice.id,
      version: version,
      current_behavior: spec.current_behavior,
      desired_behavior: spec.desired_behavior,
      key_interfaces: spec.likely_files,
      out_of_scope: spec.out_of_scope,
      risk: spec.risk,
      acceptance_criteria: spec.acceptance_criteria,
      required_tests: spec.required_tests,
      verification_commands: spec.verification_commands,
      non_goals: spec.out_of_scope,
      locked_at: now,
      locked_by: locked_by,
      contract_sha256: Map.fetch!(contract, "contract_digest")
    }
  end

  defp test_pack_attrs(slice, context, spec, version, now, locked_by) do
    manifest = test_pack_manifest(spec, context.project, version)

    %{
      slice_id: slice.id,
      version: version,
      source_ref: source_ref(spec.required_tests),
      test_pack_ref: manifest["test_pack_ref"],
      test_pack_sha256: ContractEvolution.digest_value(manifest),
      required_test_refs: Enum.map(spec.required_tests, & &1["ref"]),
      acceptance_criteria_refs: Enum.map(spec.acceptance_criteria, & &1["id"]),
      mount_path: manifest["mount_path"],
      runner_command_specs: spec.verification_commands,
      test_result_adapter: "Conveyor.TestResultAdapter.JUnit",
      locked_at: now,
      locked_by: locked_by
    }
  end

  defp contract_lock_attrs(slice, context, spec, agent_brief, test_pack, now, locked_by) do
    %{
      slice_id: slice.id,
      agent_brief_id: agent_brief.id,
      plan_contract_sha256: context.plan.contract_sha256,
      brief_sha256: agent_brief.contract_sha256,
      acceptance_criteria_sha256: ContractEvolution.digest_value(agent_brief.acceptance_criteria),
      required_tests_sha256: ContractEvolution.digest_value(agent_brief.required_tests),
      test_pack_sha256: test_pack.test_pack_sha256,
      verification_commands_sha256:
        ContractEvolution.digest_value(agent_brief.verification_commands),
      agents_md_sha256: agents_md_sha256(context.project.local_path),
      policy_sha256: ContractEvolution.digest_value(policy_contract(spec)),
      protected_path_globs: protected_path_globs(spec),
      locked_at: now,
      locked_by: locked_by
    }
  end

  defp acceptance_criteria(work_slice, plan_contract, requirement_refs) do
    work_slice
    |> list("acceptance_criteria")
    |> case do
      [] ->
        plan_contract
        |> list("acceptance_criteria")
        |> Enum.filter(fn criterion ->
          criterion
          |> string_list("requirement_refs")
          |> intersects?(requirement_refs)
        end)

      criteria ->
        criteria
    end
    |> Enum.map(&normalize_acceptance_criterion/1)
    |> case do
      [] -> raise ArgumentError, "slice has no acceptance criteria"
      criteria -> criteria
    end
  end

  defp normalize_acceptance_criterion(criterion) do
    required_test_refs = string_list(criterion, "required_test_refs")
    id = fetch(criterion, "id") || fetch(criterion, "key")

    %{
      "id" => id,
      "text" => fetch(criterion, "text") || "#{id} must pass.",
      "kind" => fetch(criterion, "kind") || "behavioral",
      "requirement_refs" => string_list(criterion, "requirement_refs"),
      "required_test_refs" => required_test_refs,
      "evidence_status" => fetch(criterion, "evidence_status") || "missing",
      "evidence_refs" => list(criterion, "evidence_refs"),
      "positive_examples" => list(criterion, "positive_examples"),
      "negative_examples" => list(criterion, "negative_examples"),
      "boundary_examples" => list(criterion, "boundary_examples"),
      "abuse_examples" => list(criterion, "abuse_examples"),
      "non_goal_examples" => list(criterion, "non_goal_examples"),
      "falsifying_conditions" =>
        non_empty(
          list(criterion, "falsifying_conditions"),
          default_falsifying_conditions(id, required_test_refs)
        ),
      "machine_checkable" => fetch(criterion, "machine_checkable") || true,
      "verification_stage" => fetch(criterion, "verification_stage") || "unit"
    }
  end

  defp default_falsifying_conditions(id, required_test_refs) do
    [
      %{
        "acceptance_criterion_id" => id,
        "condition" => "#{id} required test fails",
        "required_test_refs" => required_test_refs
      }
    ]
  end

  defp required_tests(acceptance_criteria) do
    acceptance_criteria
    |> Enum.flat_map(fn criterion ->
      Enum.map(criterion["required_test_refs"], fn test_ref ->
        %{
          "ref" => test_ref,
          "source_ref" => source_ref(test_ref),
          "acceptance_criteria_refs" => [criterion["id"]],
          "locked" => true
        }
      end)
    end)
    |> Enum.uniq_by(& &1["ref"])
  end

  defp command_specs(plan_contract, project) do
    plan_contract
    |> list("verification_commands")
    |> case do
      [] -> [%{"key" => "pytest", "argv" => ["pytest", "-q"], "profile" => "verify"}]
      commands -> commands
    end
    |> Enum.map(&command_spec(&1, project))
  end

  defp command_spec(command, project) do
    %{
      "key" => fetch_or(command, "key", "verify"),
      "argv" => list(command, "argv"),
      "cwd" => fetch_or(command, "cwd", project.local_path),
      "profile" => fetch_or(command, "profile", "verify"),
      "required" => fetch_or(command, "required", true) != false,
      "timeout_ms" => fetch_or(command, "timeout_ms", 120_000),
      "network" => fetch_or(command, "network", "none"),
      "env_allowlist" => list(command, "env_allowlist"),
      "output_limit_bytes" => fetch_or(command, "output_limit_bytes", 2_000_000),
      "repeat" => fetch_or(command, "repeat", 1),
      "flake_policy" => fetch_or(command, "flake_policy", "fail_closed"),
      "infra_retry_policy" => fetch_or(command, "infra_retry_policy", default_retry_policy()),
      "result_format" => fetch_or(command, "result_format", "junit")
    }
  end

  defp default_retry_policy, do: %{"max_retries" => 0, "retry_on" => []}

  defp test_pack_manifest(spec, project, version) do
    %{
      "schema_version" => "conveyor.test_pack@1",
      "test_pack_ref" => "first_light/#{spec.stable_key}/test-pack@v#{version}",
      "mount_path" =>
        "/workspace/.conveyor/test-packs/first_light/#{spec.stable_key}/v#{version}",
      "project_path" => project.local_path,
      "required_test_refs" => Enum.map(spec.required_tests, & &1["ref"]),
      "acceptance_criteria_refs" => Enum.map(spec.acceptance_criteria, & &1["id"])
    }
  end

  defp protected_path_globs(spec) do
    spec.required_tests
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.map(&source_ref(&1["ref"]))
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp locked_test_paths(%Slice{} = slice) do
    slice.likely_files
    |> Enum.filter(&String.starts_with?(&1, "test"))
    |> Enum.sort()
  end

  defp diff_policy_sha256(%DiffPolicy{} = diff_policy) do
    ContractEvolution.digest_value(%{
      "allowed_path_globs" => diff_policy.allowed_path_globs,
      "protected_path_globs" => diff_policy.protected_path_globs,
      "max_files_changed" => diff_policy.max_files_changed,
      "max_lines_added" => diff_policy.max_lines_added,
      "max_lines_deleted" => diff_policy.max_lines_deleted,
      "dependency_changes_allowed" => diff_policy.dependency_changes_allowed,
      "migrations_allowed" => diff_policy.migrations_allowed,
      "generated_files_allowed" => diff_policy.generated_files_allowed,
      "public_api_changes_allowed" => diff_policy.public_api_changes_allowed
    })
  end

  defp policy_contract(spec) do
    %{
      "network" => "none",
      "protected_path_globs" => protected_path_globs(spec),
      "verification_commands" => spec.verification_commands
    }
  end

  defp latest_contract!(slice_id) do
    case latest_contract(slice_id) do
      %{agent_brief: %AgentBrief{}, contract_lock: %ContractLock{}, test_pack: %TestPack{}} =
          contract ->
        contract

      _missing ->
        raise ArgumentError, "slice #{slice_id} has no materialized contract"
    end
  end

  defp latest_contract(slice_id) do
    agent_brief = latest_agent_brief(slice_id)

    %{
      agent_brief: agent_brief,
      contract_lock: latest_contract_lock(slice_id, agent_brief && agent_brief.id),
      test_pack: latest_test_pack(slice_id),
      falsifier_forge: falsifier_forge_report(agent_brief)
    }
  end

  defp falsifier_forge_report(%AgentBrief{} = agent_brief),
    do: FalsifierForge.run!(agent_brief.acceptance_criteria)

  defp falsifier_forge_report(_agent_brief), do: nil

  defp latest_agent_brief(slice_id) do
    AgentBrief
    |> Ash.read!(domain: Factory)
    |> Enum.filter(&(&1.slice_id == slice_id))
    |> Enum.sort_by(&{&1.version, DateTime.to_unix(&1.locked_at, :microsecond)}, :desc)
    |> List.first()
  end

  defp latest_contract_lock(_slice_id, nil), do: nil

  defp latest_contract_lock(slice_id, agent_brief_id) do
    ContractLock
    |> Ash.read!(domain: Factory)
    |> Enum.filter(&(&1.slice_id == slice_id and &1.agent_brief_id == agent_brief_id))
    |> Enum.sort_by(&DateTime.to_unix(&1.locked_at, :microsecond), :desc)
    |> List.first()
  end

  defp latest_test_pack(slice_id) do
    TestPack
    |> Ash.read!(domain: Factory)
    |> Enum.filter(&(&1.slice_id == slice_id))
    |> Enum.sort_by(&{&1.version, DateTime.to_unix(&1.locked_at, :microsecond)}, :desc)
    |> List.first()
  end

  defp next_contract_version(slice_id) do
    AgentBrief
    |> Ash.read!(domain: Factory)
    |> Enum.filter(&(&1.slice_id == slice_id))
    |> Enum.map(& &1.version)
    |> Enum.max(fn -> 0 end)
    |> Kernel.+(1)
  end

  defp contract_lock_sha256(%ContractLock{} = lock, _plan) do
    ContractEvolution.contract_lock_sha256(lock)
  end

  defp policy_sha256(%ContractLock{policy_sha256: sha256}), do: sha256

  defp test_pack_sha256(%TestPack{test_pack_sha256: sha256}), do: sha256

  defp run_spec_digest(slice, work_graph, base_commit, attempt_no) do
    CanonicalJson.digest(%{
      "schema_version" => "conveyor.run_spec_seed@1",
      "slice_id" => slice.id,
      "attempt_no" => attempt_no,
      "base_commit" => base_commit,
      "work_graph_digest" => CanonicalJson.digest(work_graph)
    })
  end

  defp git_head!(workspace_path) do
    {output, 0} =
      System.cmd("git", ["-C", workspace_path, "rev-parse", "HEAD"], stderr_to_stdout: true)

    String.trim(output)
  end

  defp get_by_id!(id, resource) do
    resource
    |> Ash.read!(domain: Factory)
    |> Enum.find(&(&1.id == id)) ||
      raise ArgumentError, "#{inspect(resource)} #{id} was not found"
  end

  defp module_name(nil), do: nil
  defp module_name(module) when is_atom(module), do: inspect(module)
  defp module_name(module) when is_binary(module), do: String.trim_leading(module, "Elixir.")

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp single_work_slice!(work_graph) do
    case list(work_graph, "slices") do
      [slice] -> slice
      slices -> raise ArgumentError, "expected one work graph slice, got #{length(slices)}"
    end
  end

  defp source_ref(%{"ref" => ref}), do: source_ref(ref)

  defp source_ref(required_tests) when is_list(required_tests) do
    required_tests
    |> List.first()
    |> source_ref()
  end

  defp source_ref(nil), do: nil

  defp source_ref(ref) do
    ref
    |> to_string()
    |> String.split("::", parts: 2)
    |> List.first()
  end

  defp agents_md_sha256(project_path) do
    [Path.join(project_path, "AGENTS.md"), "AGENTS.md"]
    |> Enum.find(&File.regular?/1)
    |> case do
      nil -> digest("agents-md")
      path -> path |> File.read!() |> sha256()
    end
  end

  defp fetch(map, key) when is_map(map) do
    atom_key = String.to_atom(key)

    cond do
      Map.has_key?(map, key) -> Map.fetch!(map, key)
      Map.has_key?(map, atom_key) -> Map.fetch!(map, atom_key)
      true -> nil
    end
  end

  defp fetch(_map, _key), do: nil

  defp fetch_or(map, key, default) do
    case fetch(map, key) do
      nil -> default
      value -> value
    end
  end

  defp list(map, key) do
    case fetch(map, key) do
      values when is_list(values) -> values
      nil -> []
      value -> [value]
    end
  end

  defp string_list(map, key), do: map |> list(key) |> Enum.map(&to_string/1)
  defp non_empty([], fallback), do: fallback
  defp non_empty(values, _fallback), do: values

  defp intersects?(left, right) do
    not MapSet.disjoint?(MapSet.new(left), MapSet.new(right))
  end

  defp digest(label), do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, label), case: :lower)

  defp sha256(content),
    do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, content), case: :lower)
end
