defmodule Conveyor.Readiness do
  @moduledoc """
  Validates that a Slice has a locked implementation brief before execution.
  """

  alias Conveyor.Factory
  alias Conveyor.Factory.AgentBrief
  alias Conveyor.Factory.ContractLock
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.Project
  alias Conveyor.Factory.Slice
  alias Conveyor.Factory.TestPack
  alias Conveyor.SliceLifecycle

  defmodule Result do
    @moduledoc "Readiness check result."

    @type status :: :ready | :blocked
    @type finding :: %{code: atom(), message: String.t()}

    @type t :: %__MODULE__{
            status: status(),
            slice: struct(),
            agent_brief: struct() | nil,
            contract_lock: struct() | nil,
            findings: [finding()]
          }

    @enforce_keys [:status, :slice, :findings]
    defstruct [:status, :slice, :agent_brief, :contract_lock, findings: []]
  end

  @spec check(Slice.t() | Ecto.UUID.t(), keyword()) :: Result.t()
  def check(slice_or_id, opts \\ [])

  def check(%Slice{} = slice, opts) do
    context = context_for!(slice)
    findings = findings(context)

    if findings == [] do
      mark_ready(context, opts)
    else
      %Result{
        status: :blocked,
        slice: slice,
        agent_brief: context.agent_brief,
        contract_lock: context.contract_lock,
        findings: findings
      }
    end
  end

  def check(slice_id, opts) when is_binary(slice_id) do
    Slice
    |> get_by_id!(slice_id)
    |> check(opts)
  end

  defp context_for!(slice) do
    epic = get_by_id!(Epic, slice.epic_id)
    plan = get_by_id!(Plan, epic.plan_id)
    project = get_by_id!(Project, plan.project_id)
    agent_brief = latest_brief(slice.id)
    contract_lock = latest_lock(slice.id, agent_brief && agent_brief.id)
    test_pack = latest_test_pack(slice.id)

    %{
      slice: slice,
      epic: epic,
      plan: plan,
      project: project,
      agent_brief: agent_brief,
      contract_lock: contract_lock,
      test_pack: test_pack
    }
  end

  defp findings(context) do
    []
    |> require_handoff_plan(context.plan)
    |> require_brief(context.agent_brief)
    |> require_lock(context.contract_lock)
    |> require_test_pack(context.test_pack)
    |> require_brief_fields(context.agent_brief)
    |> require_lock_digests(context)
    |> Enum.reverse()
  end

  defp require_handoff_plan(findings, %Plan{status: :handoff_ready}), do: findings

  defp require_handoff_plan(findings, %Plan{status: status}) do
    finding(findings, :plan_not_handoff_ready, "Plan must be handoff_ready; got #{status}")
  end

  defp require_brief(findings, %AgentBrief{}), do: findings

  defp require_brief(findings, nil),
    do: finding(findings, :missing_brief, "Slice has no AgentBrief")

  defp require_lock(findings, %ContractLock{}), do: findings

  defp require_lock(findings, nil) do
    finding(
      findings,
      :missing_contract_lock,
      "Slice has no ContractLock for its latest AgentBrief"
    )
  end

  defp require_test_pack(findings, %TestPack{}), do: findings

  defp require_test_pack(findings, nil),
    do: finding(findings, :missing_test_pack, "Slice has no TestPack")

  defp require_brief_fields(findings, nil), do: findings

  defp require_brief_fields(findings, %AgentBrief{} = brief) do
    findings
    |> require_non_empty(
      :missing_key_interfaces,
      brief.key_interfaces,
      "Brief has no key interfaces"
    )
    |> require_non_empty(
      :missing_out_of_scope,
      brief.out_of_scope,
      "Brief has no out-of-scope list"
    )
    |> require_non_empty(:missing_risk, brief.risk, "Brief has no risk")
    |> require_acceptance_criteria(brief.acceptance_criteria)
    |> require_required_tests(brief.required_tests)
  end

  defp require_acceptance_criteria(findings, []),
    do: finding(findings, :missing_acceptance_criteria, "Brief has no acceptance criteria")

  defp require_acceptance_criteria(findings, criteria) do
    if Enum.all?(criteria, &criterion_complete?/1) do
      findings
    else
      finding(
        findings,
        :incomplete_acceptance_criteria,
        "Brief acceptance criteria are incomplete"
      )
    end
  end

  defp require_required_tests(findings, []),
    do: finding(findings, :missing_required_tests, "Brief has no required tests")

  defp require_required_tests(findings, tests) do
    if Enum.all?(tests, &required_test_complete?/1) do
      findings
    else
      finding(findings, :incomplete_required_tests, "Brief required tests are incomplete")
    end
  end

  defp require_lock_digests(findings, %{agent_brief: nil}), do: findings
  defp require_lock_digests(findings, %{contract_lock: nil}), do: findings

  defp require_lock_digests(findings, context) do
    brief = context.agent_brief
    lock = context.contract_lock

    findings
    |> require_digest(
      :plan_contract_mismatch,
      lock.plan_contract_sha256,
      context.plan.contract_sha256
    )
    |> require_digest(:brief_mismatch, lock.brief_sha256, brief.contract_sha256)
    |> require_digest(
      :acceptance_criteria_mismatch,
      lock.acceptance_criteria_sha256,
      digest_value(brief.acceptance_criteria)
    )
    |> require_digest(
      :required_tests_mismatch,
      lock.required_tests_sha256,
      digest_value(brief.required_tests)
    )
    |> require_digest(
      :verification_commands_mismatch,
      lock.verification_commands_sha256,
      digest_value(brief.verification_commands)
    )
    |> require_test_pack_digest(lock, context.test_pack)
  end

  defp require_test_pack_digest(findings, _lock, nil), do: findings

  defp require_test_pack_digest(findings, lock, test_pack) do
    require_digest(
      findings,
      :test_pack_mismatch,
      lock.test_pack_sha256,
      test_pack.test_pack_sha256
    )
  end

  defp require_digest(findings, _code, expected, expected), do: findings

  defp require_digest(findings, code, expected, actual) do
    finding(findings, code, "ContractLock digest mismatch: expected #{expected}, got #{actual}")
  end

  defp mark_ready(context, opts) do
    slice =
      if context.slice.state == :ready do
        context.slice
      else
        SliceLifecycle.transition!(context.slice, :mark_ready,
          actor: Keyword.get(opts, :actor, "readiness"),
          reason: "readiness check passed"
        )
      end

    %Result{
      status: :ready,
      slice: slice,
      agent_brief: context.agent_brief,
      contract_lock: context.contract_lock,
      findings: []
    }
  rescue
    error ->
      %Result{
        status: :blocked,
        slice: context.slice,
        agent_brief: context.agent_brief,
        contract_lock: context.contract_lock,
        findings: [finding(:slice_transition_failed, Exception.message(error))]
      }
  end

  defp criterion_complete?(criterion) do
    filled?(criterion["id"]) and filled?(criterion["text"]) and
      non_empty?(criterion["required_test_refs"])
  end

  defp required_test_complete?(test) do
    filled?(test["ref"]) and filled?(test["source_ref"]) and test["locked"] == true
  end

  defp require_non_empty(findings, _code, value, _message) when is_binary(value) and value != "",
    do: findings

  defp require_non_empty(findings, _code, value, _message) when is_list(value) and value != [],
    do: findings

  defp require_non_empty(findings, code, _value, message), do: finding(findings, code, message)

  defp non_empty?(value), do: is_list(value) and value != []
  defp filled?(value), do: is_binary(value) and String.trim(value) != ""

  defp finding(findings, code, message), do: [finding(code, message) | findings]
  defp finding(code, message), do: %{code: code, message: message}

  defp latest_brief(slice_id) do
    AgentBrief
    |> Ash.read!(domain: Factory)
    |> Enum.filter(&(&1.slice_id == slice_id))
    |> Enum.sort_by(&{&1.version, DateTime.to_unix(&1.locked_at, :microsecond)}, :desc)
    |> List.first()
  end

  defp latest_lock(_slice_id, nil), do: nil

  defp latest_lock(slice_id, agent_brief_id) do
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

  defp get_by_id!(resource, id) do
    resource
    |> Ash.read!(domain: Factory)
    |> Enum.find(&(&1.id == id)) ||
      raise ArgumentError, "#{inspect(resource)} #{id} was not found"
  end

  defp digest_value(value), do: "sha256:" <> sha256(canonical_json(value))

  defp canonical_json(%DateTime{} = value), do: value |> DateTime.to_iso8601() |> Jason.encode!()

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

  defp sha256(content), do: Base.encode16(:crypto.hash(:sha256, content), case: :lower)
end
