defmodule Conveyor.ContractEvolution do
  @moduledoc """
  Classifies contract changes and materializes rerun state for changed contracts.
  """

  alias Conveyor.Factory
  alias Conveyor.Factory.AgentBrief
  alias Conveyor.Factory.ContractLock
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.HumanDecision
  alias Conveyor.Factory.RunAttempt
  alias Conveyor.Factory.RunSpec
  alias Conveyor.Factory.Slice

  defmodule Diff do
    @moduledoc false

    @type t :: %__MODULE__{
            classifications: [atom()],
            changed?: boolean(),
            automatic_rerun_allowed?: boolean(),
            requires_human_decision?: boolean()
          }

    @enforce_keys [
      :classifications,
      :changed?,
      :automatic_rerun_allowed?,
      :requires_human_decision?
    ]
    defstruct [
      :classifications,
      :changed?,
      :automatic_rerun_allowed?,
      :requires_human_decision?
    ]
  end

  defmodule Rerun do
    @moduledoc false

    @enforce_keys [:diff, :contract_lock, :run_spec, :run_attempt, :human_decision]
    defstruct [:diff, :contract_lock, :run_spec, :run_attempt, :human_decision]
  end

  @classification_order [
    :acceptance_weakened,
    :acceptance_strengthened,
    :policy_weakened,
    :policy_strengthened,
    :scope_added,
    :scope_removed,
    :test_pack_changed,
    :clarification_only
  ]
  @weakening [:acceptance_weakened, :policy_weakened]

  @spec diff(map() | struct(), map() | struct()) :: Diff.t()
  def diff(old_contract, new_contract) do
    old = normalize_contract(old_contract)
    new = normalize_contract(new_contract)

    classifications =
      []
      |> maybe_add(removed?(old.acceptance_keys, new.acceptance_keys), :acceptance_weakened)
      |> maybe_add(added?(old.acceptance_keys, new.acceptance_keys), :acceptance_strengthened)
      |> maybe_add(removed?(old.protected_path_globs, new.protected_path_globs), :policy_weakened)
      |> maybe_add(
        added?(old.protected_path_globs, new.protected_path_globs),
        :policy_strengthened
      )
      |> maybe_add(added?(old.scope, new.scope), :scope_added)
      |> maybe_add(removed?(old.scope, new.scope), :scope_removed)
      |> maybe_add(changed?(old.test_pack_sha256, new.test_pack_sha256), :test_pack_changed)
      |> maybe_add(clarification_only?(old, new), :clarification_only)
      |> order_classifications()

    weakening? = Enum.any?(classifications, &(&1 in @weakening))

    %Diff{
      classifications: classifications,
      changed?: classifications != [],
      automatic_rerun_allowed?: not weakening?,
      requires_human_decision?: classifications != []
    }
  end

  @spec prepare_rerun!(RunAttempt.t() | Ecto.UUID.t(), map(), keyword()) :: Rerun.t()
  def prepare_rerun!(run_attempt_or_id, proposed_contract, opts \\ []) do
    now = Keyword.get_lazy(opts, :now, fn -> DateTime.utc_now(:microsecond) end)
    actor = Keyword.get(opts, :actor, "operator")
    human_reason = Keyword.get(opts, :human_reason)
    run_attempt = get_run_attempt!(run_attempt_or_id)
    run_spec = get_by_id!(RunSpec, run_attempt.run_spec_id)
    old_contract_lock = contract_lock_for_run_spec!(run_spec)
    old_agent_brief = get_by_id!(AgentBrief, old_contract_lock.agent_brief_id)
    old_contract = contract_context(old_contract_lock, old_agent_brief)
    new_contract = merge_contract(old_contract, proposed_contract)
    contract_diff = diff(old_contract, new_contract)

    if Enum.any?(contract_diff.classifications, &(&1 in @weakening)) and blank?(human_reason) do
      raise ArgumentError, "human approval reason is required for weakening contract changes"
    end

    if not contract_diff.changed? do
      raise ArgumentError, "contract rerun requires a contract-affecting change"
    end

    next_attempt_no = next_attempt_no(run_attempt.slice_id)
    contract_lock = create_contract_lock!(old_contract_lock, new_contract, now, actor)
    run_spec = create_run_spec!(run_spec, contract_lock, next_attempt_no)

    rerun_attempt =
      Ash.create!(
        RunAttempt,
        %{
          slice_id: run_attempt.slice_id,
          run_spec_id: run_spec.id,
          attempt_no: next_attempt_no,
          base_commit: run_spec.base_commit,
          status: :planned,
          outcome: :none,
          orchestrator_version: run_attempt.orchestrator_version,
          trace_id: run_attempt.trace_id <> ":attempt-#{next_attempt_no}"
        },
        domain: Factory
      )

    human_decision =
      create_human_decision!(
        run_attempt.slice_id,
        next_attempt_no,
        run_spec.contract_lock_sha256,
        human_reason || "Contract changed before rerun.",
        contract_diff
      )

    %Rerun{
      diff: contract_diff,
      contract_lock: contract_lock,
      run_spec: run_spec,
      run_attempt: rerun_attempt,
      human_decision: human_decision
    }
  end

  @spec contract_lock_sha256(ContractLock.t()) :: String.t()
  def contract_lock_sha256(%ContractLock{} = contract_lock),
    do: digest_value(contract_lock_payload(contract_lock))

  @spec digest_value(term()) :: String.t()
  def digest_value(value),
    do: "sha256:" <> Base.encode16(:crypto.hash(:sha256, canonical_json(value)), case: :lower)

  defp create_contract_lock!(old, new_contract, now, actor) do
    protected_path_globs =
      new_contract
      |> Map.fetch!(:protected_path_globs)
      |> set_to_list()

    Ash.create!(
      ContractLock,
      %{
        slice_id: old.slice_id,
        agent_brief_id: old.agent_brief_id,
        plan_contract_sha256: Map.fetch!(new_contract, :plan_contract_sha256),
        brief_sha256: Map.fetch!(new_contract, :brief_sha256),
        acceptance_criteria_sha256: digest_value(Map.fetch!(new_contract, :acceptance_criteria)),
        required_tests_sha256: digest_value(Map.fetch!(new_contract, :required_tests)),
        test_pack_sha256: Map.fetch!(new_contract, :test_pack_sha256),
        verification_commands_sha256: Map.fetch!(new_contract, :verification_commands_sha256),
        agents_md_sha256: Map.fetch!(new_contract, :agents_md_sha256),
        policy_sha256: digest_value(%{"protected_path_globs" => protected_path_globs}),
        protected_path_globs: protected_path_globs,
        locked_at: now,
        locked_by: actor
      },
      domain: Factory
    )
  end

  defp create_run_spec!(old_run_spec, contract_lock, attempt_no) do
    contract_lock_sha256 = contract_lock_sha256(contract_lock)

    run_spec_seed = %{
      "slice_id" => old_run_spec.slice_id,
      "attempt_no" => attempt_no,
      "base_commit" => old_run_spec.base_commit,
      "contract_lock_sha256" => contract_lock_sha256,
      "test_pack_sha256" => contract_lock.test_pack_sha256
    }

    run_spec_sha256 = digest_value(run_spec_seed)

    Ash.create!(
      RunSpec,
      %{
        slice_id: old_run_spec.slice_id,
        attempt_no: attempt_no,
        run_spec_json_ref: "artifacts/run-specs/attempt-#{attempt_no}.json",
        run_spec_sha256: run_spec_sha256,
        base_commit: old_run_spec.base_commit,
        contract_lock_sha256: contract_lock_sha256,
        prompt_template_version: old_run_spec.prompt_template_version,
        agent_profile_snapshot: old_run_spec.agent_profile_snapshot,
        policy_sha256: contract_lock.policy_sha256,
        diff_policy_sha256: old_run_spec.diff_policy_sha256,
        test_pack_sha256: contract_lock.test_pack_sha256,
        station_plan: station_plan_for_attempt(old_run_spec.station_plan, run_spec_sha256),
        station_plan_sha256:
          digest_value(station_plan_for_attempt(old_run_spec.station_plan, run_spec_sha256)),
        container_image_ref: old_run_spec.container_image_ref,
        container_image_digest: old_run_spec.container_image_digest,
        sandbox_profile: old_run_spec.sandbox_profile,
        budget_sha256: old_run_spec.budget_sha256,
        code_quality_profile: old_run_spec.code_quality_profile,
        canary_suite_version: old_run_spec.canary_suite_version
      },
      domain: Factory
    )
  end

  defp create_human_decision!(slice_id, attempt_no, contract_sha256, rationale, contract_diff) do
    slice = get_by_id!(Slice, slice_id)
    epic = get_by_id!(Epic, slice.epic_id)

    Ash.create!(
      HumanDecision,
      %{
        plan_id: epic.plan_id,
        stable_key: "contract-evolution:#{slice_id}:attempt-#{attempt_no}",
        decision: "Contract evolution approved for rerun.",
        rationale: rationale,
        section_ref: "contract-evolution",
        source_span: %{
          "classifications" => Enum.map(contract_diff.classifications, &Atom.to_string/1)
        },
        contract_sha256: contract_sha256,
        status: :active
      },
      domain: Factory
    )
  end

  defp contract_lock_for_run_spec!(run_spec) do
    ContractLock
    |> Ash.read!(domain: Factory)
    |> Enum.find(&(contract_lock_sha256(&1) == run_spec.contract_lock_sha256)) ||
      raise ArgumentError, "ContractLock for RunSpec #{run_spec.id} was not found"
  end

  defp contract_context(contract_lock, agent_brief) do
    %{
      acceptance_criteria: agent_brief.acceptance_criteria,
      agents_md_sha256: contract_lock.agents_md_sha256,
      brief_sha256: contract_lock.brief_sha256,
      plan_contract_sha256: contract_lock.plan_contract_sha256,
      policy: %{"protected_path_globs" => contract_lock.protected_path_globs},
      protected_path_globs: contract_lock.protected_path_globs,
      required_tests: agent_brief.required_tests,
      scope: agent_brief.key_interfaces,
      test_pack_sha256: contract_lock.test_pack_sha256,
      verification_commands_sha256: contract_lock.verification_commands_sha256
    }
  end

  defp merge_contract(old_contract, proposed_contract) do
    proposed = atomize_keys(proposed_contract)
    policy = Map.get(proposed, :policy, Map.get(old_contract, :policy))

    protected_path_globs =
      Map.get(proposed, :protected_path_globs, policy |> protected_path_globs() |> set_to_list())

    old_contract
    |> Map.merge(proposed)
    |> Map.put(:policy, policy)
    |> Map.put(:protected_path_globs, protected_path_globs)
    |> Map.put_new_lazy(:brief_sha256, fn ->
      digest_value(%{
        "acceptance_criteria" => Map.get(proposed, :acceptance_criteria),
        "required_tests" => Map.get(proposed, :required_tests),
        "scope" => Map.get(proposed, :scope)
      })
    end)
  end

  defp normalize_contract(%_{} = contract),
    do: contract |> Map.from_struct() |> normalize_contract()

  defp normalize_contract(contract) when is_map(contract) do
    contract = atomize_keys(contract)
    policy = Map.get(contract, :policy, %{})
    acceptance = list(contract, :acceptance_criteria)
    required_tests = list(contract, :required_tests)

    %{
      acceptance_keys: MapSet.union(stable_key_set(acceptance), stable_key_set(required_tests)),
      protected_path_globs: protected_path_globs(policy, contract),
      scope: stable_key_set(list(contract, :scope) ++ list(contract, :key_interfaces)),
      test_pack_sha256: Map.get(contract, :test_pack_sha256),
      raw: contract
    }
  end

  defp normalize_contract(contract), do: contract |> Map.new() |> normalize_contract()

  defp protected_path_globs(policy, contract \\ %{}) do
    paths =
      Map.get(contract, :protected_path_globs) ||
        Map.get(policy, :protected_path_globs) ||
        Map.get(policy, "protected_path_globs") ||
        []

    MapSet.new(paths)
  end

  defp set_to_list(%MapSet{} = set), do: MapSet.to_list(set)
  defp set_to_list(values), do: values

  defp list(contract, key) do
    case Map.get(contract, key) do
      values when is_list(values) -> values
      nil -> []
      value -> [value]
    end
  end

  defp stable_key_set(values) do
    values
    |> Enum.map(&stable_key/1)
    |> MapSet.new()
  end

  defp stable_key(value) when is_binary(value), do: value
  defp stable_key(value) when is_atom(value), do: Atom.to_string(value)

  defp stable_key(value) when is_map(value) do
    Map.get(value, "id") ||
      Map.get(value, :id) ||
      Map.get(value, "ref") ||
      Map.get(value, :ref) ||
      Map.get(value, "key") ||
      Map.get(value, :key) ||
      Map.get(value, "name") ||
      Map.get(value, :name) ||
      digest_value(value)
  end

  defp stable_key(value), do: inspect(value)

  defp removed?(old_set, new_set), do: not MapSet.subset?(old_set, new_set)
  defp added?(old_set, new_set), do: not MapSet.subset?(new_set, old_set)
  defp changed?(nil, _new), do: false
  defp changed?(_old, nil), do: false
  defp changed?(old, new), do: old != new

  defp clarification_only?(old, new) do
    old.raw != new.raw and
      not removed?(old.acceptance_keys, new.acceptance_keys) and
      not added?(old.acceptance_keys, new.acceptance_keys) and
      not removed?(old.protected_path_globs, new.protected_path_globs) and
      not added?(old.protected_path_globs, new.protected_path_globs) and
      not removed?(old.scope, new.scope) and
      not added?(old.scope, new.scope) and
      not changed?(old.test_pack_sha256, new.test_pack_sha256)
  end

  defp maybe_add(classifications, true, classification), do: [classification | classifications]
  defp maybe_add(classifications, false, _classification), do: classifications

  defp order_classifications(classifications) do
    Enum.filter(@classification_order, &(&1 in classifications))
  end

  defp next_attempt_no(slice_id) do
    RunAttempt
    |> Ash.read!(domain: Factory)
    |> Enum.filter(&(&1.slice_id == slice_id))
    |> Enum.map(& &1.attempt_no)
    |> Enum.max(fn -> 0 end)
    |> Kernel.+(1)
  end

  defp station_plan_for_attempt(station_plan, run_spec_sha256) do
    stations =
      station_plan
      |> Map.fetch!("stations")
      |> Enum.map(fn station ->
        station
        |> put_in(["input", "run_spec_sha256"], run_spec_sha256)
        |> put_in(["output", "run_spec_sha256"], run_spec_sha256)
      end)

    Map.put(station_plan, "stations", stations)
  end

  defp get_run_attempt!(%RunAttempt{} = run_attempt), do: run_attempt
  defp get_run_attempt!(id), do: get_by_id!(RunAttempt, id)

  defp get_by_id!(resource, id) do
    resource
    |> Ash.read!(domain: Factory)
    |> Enum.find(&(&1.id == id)) ||
      raise ArgumentError, "#{inspect(resource)} #{id} was not found"
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

  defp atomize_keys(value) when is_map(value) do
    Map.new(value, fn
      {key, nested} when is_binary(key) -> {String.to_atom(key), atomize_keys(nested)}
      {key, nested} -> {key, atomize_keys(nested)}
    end)
  end

  defp atomize_keys(values) when is_list(values), do: Enum.map(values, &atomize_keys/1)
  defp atomize_keys(value), do: value

  defp canonical_json(value), do: Jason.encode!(normalize_for_json(value))

  defp normalize_for_json(%DateTime{} = value), do: DateTime.to_iso8601(value)

  defp normalize_for_json(value) when is_map(value) do
    value
    |> Enum.map(fn {key, nested} -> {to_string(key), normalize_for_json(nested)} end)
    |> Enum.sort_by(&elem(&1, 0))
    |> Map.new()
  end

  defp normalize_for_json(values) when is_list(values),
    do: Enum.map(values, &normalize_for_json/1)

  defp normalize_for_json(value), do: value

  defp blank?(value), do: is_nil(value) or (is_binary(value) and String.trim(value) == "")
end
