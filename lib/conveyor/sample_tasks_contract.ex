defmodule Conveyor.SampleTasksContract do
  @moduledoc """
  Builds the locked first-slice handoff contract for the sample tasks service.

  The human-authored plan is the source of truth. This module normalizes the
  first slice into AgentBrief, TestPack, and ContractLock attributes with stable
  digests so later seed tasks can persist the same contract idempotently.
  """

  alias Conveyor.PlanContract

  @sample_plan_path "samples/tasks_service/plan.md"
  @agents_md_path "AGENTS.md"
  @source_test_ref "samples/tasks_service/tests/test_tasks_api.py"
  @locked_pack_file "samples/tasks_service/.conveyor/test-packs/tasks-complete/v1/tests/test_tasks_api.py"
  @test_pack_ref "sample_tasks/SLICE-001/test-packs/tasks-complete@v1"
  @mount_path "/workspace/.conveyor/test-packs/sample_tasks/tasks-complete/v1"
  @result_path "/workspace/.conveyor/results/sample_tasks_SLICE-001.xml"
  @protected_path_globs [
    "samples/tasks_service/conveyor.plan.yml",
    "samples/tasks_service/plan.md",
    "samples/tasks_service/.conveyor/test-packs/tasks-complete/v1/**"
  ]

  @type attrs :: %{required(atom()) => term()}

  @spec agent_brief_attrs!(Ecto.UUID.t(), keyword()) :: attrs()
  def agent_brief_attrs!(slice_id, opts \\ []) do
    inputs = inputs!(opts)
    acceptance_criteria = acceptance_criteria(inputs.contract)
    required_tests = required_tests(acceptance_criteria)
    verification_commands = command_specs(inputs.contract)

    attrs = %{
      slice_id: slice_id,
      version: 1,
      current_behavior: "The sample tasks API supports creating tasks and listing them in order.",
      desired_behavior: Map.fetch!(inputs.contract, "goal"),
      key_interfaces: ["GET /tasks", "POST /tasks", "PATCH /tasks/{id}"],
      out_of_scope: Map.fetch!(inputs.contract, "non_goals"),
      risk: slice_risk(inputs.contract),
      acceptance_criteria: acceptance_criteria,
      required_tests: required_tests,
      verification_commands: verification_commands,
      non_goals: Map.fetch!(inputs.contract, "non_goals"),
      locked_at: inputs.locked_at,
      locked_by: inputs.locked_by
    }

    Map.put(attrs, :contract_sha256, digest_value(brief_contract(inputs, attrs)))
  end

  @spec test_pack_attrs!(Ecto.UUID.t(), keyword()) :: attrs()
  def test_pack_attrs!(slice_id, opts \\ []) do
    inputs = inputs!(opts)
    acceptance_criteria = acceptance_criteria(inputs.contract)

    %{
      slice_id: slice_id,
      version: 1,
      source_ref: @source_test_ref,
      test_pack_ref: @test_pack_ref,
      test_pack_sha256: test_pack_sha256!(opts),
      required_test_refs: required_test_refs(acceptance_criteria),
      acceptance_criteria_refs: acceptance_criteria_refs(acceptance_criteria),
      mount_path: @mount_path,
      runner_command_specs: locked_pack_command_specs(inputs.contract),
      test_result_adapter: "Conveyor.TestResultAdapter.JUnit",
      locked_at: inputs.locked_at,
      locked_by: inputs.locked_by
    }
  end

  @spec contract_lock_attrs!(Ecto.UUID.t(), Ecto.UUID.t(), keyword()) :: attrs()
  def contract_lock_attrs!(slice_id, agent_brief_id, opts \\ []) do
    inputs = inputs!(opts)
    acceptance_criteria = acceptance_criteria(inputs.contract)
    required_tests = required_tests(acceptance_criteria)
    verification_commands = command_specs(inputs.contract)
    brief_attrs = agent_brief_attrs!(slice_id, opts)

    %{
      slice_id: slice_id,
      agent_brief_id: agent_brief_id,
      plan_contract_sha256: inputs.contract_result.contract_sha256,
      brief_sha256: Map.fetch!(brief_attrs, :contract_sha256),
      acceptance_criteria_sha256: digest_value(acceptance_criteria),
      required_tests_sha256: digest_value(required_tests),
      test_pack_sha256: test_pack_sha256!(opts),
      verification_commands_sha256: digest_value(verification_commands),
      agents_md_sha256: file_sha256!(inputs.repo_root, @agents_md_path),
      policy_sha256: digest_value(policy_contract(inputs, verification_commands)),
      protected_path_globs: protected_path_globs(),
      locked_at: inputs.locked_at,
      locked_by: inputs.locked_by
    }
  end

  @spec test_pack_manifest!(keyword()) :: map()
  def test_pack_manifest!(opts \\ []) do
    inputs = inputs!(opts)
    acceptance_criteria = acceptance_criteria(inputs.contract)

    %{
      "schema_version" => "conveyor.test_pack@1",
      "test_pack_ref" => @test_pack_ref,
      "mount_path" => @mount_path,
      "files" => [
        %{
          "path" => "tests/test_tasks_api.py",
          "sha256" => file_sha256!(inputs.repo_root, @locked_pack_file)
        }
      ],
      "required_test_refs" => required_test_refs(acceptance_criteria),
      "acceptance_criteria_refs" => acceptance_criteria_refs(acceptance_criteria)
    }
  end

  @spec test_pack_sha256!(keyword()) :: String.t()
  def test_pack_sha256!(opts \\ []), do: digest_value(test_pack_manifest!(opts))

  @spec protected_path_globs() :: [String.t()]
  def protected_path_globs, do: @protected_path_globs

  defp inputs!(opts) do
    repo_root = Keyword.get_lazy(opts, :repo_root, &repo_root/0)
    plan_path = Keyword.get(opts, :plan_path, Path.join(repo_root, @sample_plan_path))

    {:ok, contract_result} = PlanContract.load(plan_path)

    %{
      repo_root: repo_root,
      contract_result: contract_result,
      contract: contract_result.contract,
      slice: first_slice!(contract_result.contract),
      locked_at: Keyword.get_lazy(opts, :locked_at, fn -> DateTime.utc_now(:microsecond) end),
      locked_by: Keyword.get(opts, :locked_by, "human-test-architect")
    }
  end

  defp first_slice!(contract) do
    contract
    |> Map.fetch!("slices")
    |> Enum.find(&(Map.fetch!(&1, "key") == "SLICE-001"))
  end

  defp acceptance_criteria(contract) do
    contract
    |> Map.fetch!("acceptance_criteria")
    |> Enum.map(fn criterion ->
      %{
        "id" => Map.fetch!(criterion, "key"),
        "text" => Map.fetch!(criterion, "text"),
        "kind" => "behavioral",
        "requirement_refs" => Map.fetch!(criterion, "requirement_refs"),
        "required_test_refs" => Map.fetch!(criterion, "required_test_refs"),
        "evidence_status" => "missing",
        "evidence_refs" => []
      }
    end)
  end

  defp required_tests(acceptance_criteria) do
    acceptance_criteria
    |> Enum.flat_map(fn criterion ->
      criterion
      |> Map.fetch!("required_test_refs")
      |> Enum.map(fn test_ref ->
        %{
          "ref" => test_ref,
          "source_ref" => @source_test_ref,
          "acceptance_criteria_refs" => [Map.fetch!(criterion, "id")],
          "locked" => true
        }
      end)
    end)
    |> Enum.uniq_by(&Map.fetch!(&1, "ref"))
  end

  defp required_test_refs(acceptance_criteria) do
    acceptance_criteria
    |> Enum.flat_map(&Map.fetch!(&1, "required_test_refs"))
    |> Enum.uniq()
  end

  defp acceptance_criteria_refs(acceptance_criteria) do
    Enum.map(acceptance_criteria, &Map.fetch!(&1, "id"))
  end

  defp command_specs(contract) do
    contract
    |> Map.fetch!("verification_commands")
    |> Enum.map(&command_spec/1)
  end

  defp locked_pack_command_specs(contract) do
    contract
    |> Map.fetch!("verification_commands")
    |> Enum.map(fn command ->
      command
      |> command_spec()
      |> Map.put(
        "argv",
        Map.fetch!(command, "argv") ++ [locked_test_path(), "--junitxml=#{@result_path}"]
      )
    end)
  end

  defp command_spec(command) do
    %{
      "key" => Map.fetch!(command, "key"),
      "argv" => Map.fetch!(command, "argv"),
      "cwd" => "samples/tasks_service",
      "profile" => Map.fetch!(command, "profile"),
      "required" => true,
      "timeout_ms" => 120_000,
      "network" => "none",
      "env_allowlist" => [],
      "output_limit_bytes" => 2_000_000,
      "repeat" => 1,
      "flake_policy" => "fail_closed",
      "infra_retry_policy" => %{"max_retries" => 0, "retry_on" => []},
      "result_format" => "junit"
    }
  end

  defp locked_test_path, do: Path.join(@mount_path, "tests/test_tasks_api.py")

  defp brief_contract(inputs, attrs) do
    %{
      "slice_key" => Map.fetch!(inputs.slice, "key"),
      "version" => Map.fetch!(attrs, :version),
      "current_behavior" => Map.fetch!(attrs, :current_behavior),
      "desired_behavior" => Map.fetch!(attrs, :desired_behavior),
      "key_interfaces" => Map.fetch!(attrs, :key_interfaces),
      "out_of_scope" => Map.fetch!(attrs, :out_of_scope),
      "risk" => Map.fetch!(attrs, :risk),
      "acceptance_criteria" => Map.fetch!(attrs, :acceptance_criteria),
      "required_tests" => Map.fetch!(attrs, :required_tests),
      "verification_commands" => Map.fetch!(attrs, :verification_commands),
      "non_goals" => Map.fetch!(attrs, :non_goals),
      "locked_at" => DateTime.to_iso8601(Map.fetch!(attrs, :locked_at)),
      "locked_by" => Map.fetch!(attrs, :locked_by)
    }
  end

  defp policy_contract(inputs, verification_commands) do
    %{
      "slice_key" => Map.fetch!(inputs.slice, "key"),
      "autonomy_ceiling" => Map.fetch!(inputs.slice, "autonomy_ceiling"),
      "network" => "none",
      "verification_commands" => verification_commands,
      "protected_path_globs" => protected_path_globs()
    }
  end

  defp slice_risk(contract) do
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

  defp file_sha256!(repo_root, relative_path) do
    repo_root
    |> Path.join(relative_path)
    |> File.read!()
    |> sha256()
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
