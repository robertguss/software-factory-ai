defmodule Conveyor.PlanContractTest do
  use ExUnit.Case, async: true

  alias Conveyor.PlanContract
  alias Conveyor.PlanContract.Error

  @valid_example Path.expand("../../docs/schemas/examples/conveyor.plan.valid.json", __DIR__)
  @sample_tasks_plan Path.expand("../../samples/tasks_service/plan.md", __DIR__)
  @invalid_missing_schema Path.expand(
                            "../../docs/schemas/examples/conveyor.plan.invalid.missing-schema-version.json",
                            __DIR__
                          )

  test "loads and validates a JSON plan contract directly" do
    assert {:ok, result} = PlanContract.load(@valid_example)

    assert result.source_path == @valid_example
    assert result.contract["schema_version"] == PlanContract.supported_schema_version()
    assert result.contract_sha256 =~ ~r/^sha256:[0-9a-f]{64}$/
  end

  test "loads a sidecar conveyor.plan.yml next to markdown prose" do
    dir = temp_dir()
    plan_path = Path.join(dir, "plan.md")
    sidecar_path = Path.join(dir, "conveyor.plan.yml")

    File.write!(plan_path, "# Project Goal\n\nHuman-readable prose.\n")
    File.write!(sidecar_path, valid_yaml_contract())

    assert {:ok, result} = PlanContract.load(plan_path)
    assert result.source_path == sidecar_path
    assert result.contract["project"]["key"] == "sample_tasks"
  end

  test "loads the Phase 1 sample tasks plan contract" do
    assert {:ok, result} = PlanContract.load(@sample_tasks_plan)

    assert result.contract["project"]["key"] == "sample_tasks"

    assert Enum.map(result.contract["requirements"], & &1["key"]) == [
             "REQ-001",
             "REQ-002",
             "REQ-003",
             "REQ-004"
           ]

    assert result.contract["slices"] |> hd() |> Map.fetch!("autonomy_ceiling") == "L1"

    required_tests =
      result.contract["acceptance_criteria"]
      |> Enum.flat_map(& &1["required_test_refs"])

    assert "tests/test_tasks_api.py::test_complete_task" in required_tests
  end

  test "loads a fenced conveyor-plan@1 block from markdown" do
    path = Path.join(temp_dir(), "plan.md")

    File.write!(path, """
    # Project Goal

    Human-readable prose.

    ```yaml conveyor-plan@1
    #{valid_yaml_contract()}
    ```
    """)

    assert {:ok, result} = PlanContract.load(path)
    assert result.source_path == path
    assert result.contract["slices"] |> hd() |> Map.fetch!("key") == "SLICE-001"
  end

  test "canonical hash is stable across object key order" do
    dir = temp_dir()
    first = Path.join(dir, "first.json")
    second = Path.join(dir, "second.json")

    first_contract = File.read!(@valid_example)
    second_contract = Jason.encode!(reordered_valid_contract())

    File.write!(first, first_contract)
    File.write!(second, second_contract)

    assert {:ok, first_result} = PlanContract.load(first)
    assert {:ok, second_result} = PlanContract.load(second)
    assert first_result.contract_sha256 == second_result.contract_sha256
  end

  test "prose-only markdown is not accepted as a normalized contract" do
    path = Path.join(temp_dir(), "plan.md")
    File.write!(path, "# Goal\n\nMake the project better.\n")

    assert {:error, %Error{code: :missing_normalized_contract}} = PlanContract.load(path)
  end

  test "missing schema_version fails explicitly before schema validation" do
    assert {:error, %Error{code: :unsupported_schema_version, message: message}} =
             PlanContract.load(@invalid_missing_schema)

    assert message =~ "missing plan schema_version"
  end

  test "loads a plan that declares an optional work_dependencies graph" do
    path = Path.join(temp_dir(), "with_deps.json")

    File.write!(path, Jason.encode!(contract_with_work_dependencies()))

    assert {:ok, result} = PlanContract.load(path)

    assert result.contract["work_dependencies"] == [
             %{"from" => "SLICE-001", "to" => "SLICE-002", "kind" => "execution_hard"},
             %{"from" => "SLICE-001", "to" => "SLICE-003", "kind" => "integration_order"}
           ]
  end

  test "rejects a work_dependency with an unknown kind" do
    path = Path.join(temp_dir(), "bad_dep_kind.json")

    bad =
      contract_with_work_dependencies()
      |> put_in(["work_dependencies", Access.at(0), "kind"], "wishful")

    File.write!(path, Jason.encode!(bad))

    assert {:error, %Error{code: :schema_validation_failed}} = PlanContract.load(path)
  end

  test "rejects a work_dependency carrying unknown properties" do
    path = Path.join(temp_dir(), "bad_dep_extra.json")

    bad =
      contract_with_work_dependencies()
      |> put_in(["work_dependencies", Access.at(0), "weight"], 5)

    File.write!(path, Jason.encode!(bad))

    assert {:error, %Error{code: :schema_validation_failed}} = PlanContract.load(path)
  end

  test "schema violations fail with schema_validation_failed" do
    path = Path.join(temp_dir(), "invalid.json")

    @valid_example
    |> File.read!()
    |> Jason.decode!()
    |> put_in(["project"], %{"key" => "sample_tasks"})
    |> Jason.encode!()
    |> then(&File.write!(path, &1))

    assert {:error, %Error{code: :schema_validation_failed, details: details}} =
             PlanContract.load(path)

    assert is_map(details)
  end

  defp contract_with_work_dependencies do
    base = @valid_example |> File.read!() |> Jason.decode!()

    extra_slices =
      Enum.map(["SLICE-002", "SLICE-003"], fn key ->
        %{
          "key" => key,
          "title" => "Slice #{key}",
          "requirement_refs" => ["REQ-001"],
          "likely_files" => ["app/#{String.downcase(key)}.py"],
          "conflict_domains" => ["tasks_api"],
          "autonomy_ceiling" => "L1"
        }
      end)

    base
    |> Map.update!("slices", &(&1 ++ extra_slices))
    |> Map.put("work_dependencies", [
      %{"from" => "SLICE-001", "to" => "SLICE-002", "kind" => "execution_hard"},
      %{"from" => "SLICE-001", "to" => "SLICE-003", "kind" => "integration_order"}
    ])
  end

  defp temp_dir do
    path =
      Path.join(System.tmp_dir!(), "conveyor-plan-contract-#{System.unique_integer([:positive])}")

    # Clean any leftover from a prior run: System.unique_integer resets per VM, so the
    # same path recurs across runs and these dirs are never auto-removed. A stale
    # conveyor.plan.yml sidecar would make the fenced-block test's load find the sidecar
    # instead of the fenced contract — a cross-run isolation flake (see commit 353827e).
    File.rm_rf!(path)
    File.mkdir_p!(path)
    path
  end

  defp valid_yaml_contract do
    """
    schema_version: conveyor.plan@1
    project:
      key: sample_tasks
      base_ref: main
    goal: Extend the sample tasks API so tasks can be marked complete.
    non_goals:
      - Authentication
      - Pagination
    requirements:
      - key: REQ-001
        text: New tasks expose completed:false by default.
        risk: low
        source_ref: plan.md#requirement-req-001
        status: covered
    acceptance_criteria:
      - key: AC-001
        text: New tasks include completed:false.
        requirement_refs:
          - REQ-001
        required_test_refs:
          - tests/test_tasks.py::test_create_defaults_completed_false
    verification_commands:
      - key: pytest
        argv:
          - pytest
          - -q
        profile: verify
    decisions:
      - key: DEC-001
        decision: Do not add authentication in Phase 1.
        rationale: Keep the tracer bullet focused on one low-risk API behavior.
    slices:
      - key: SLICE-001
        title: Add complete-a-task endpoint
        requirement_refs:
          - REQ-001
        likely_files:
          - app/main.py
          - tests/test_tasks.py
        conflict_domains:
          - tasks_api
        autonomy_ceiling: L1
    """
  end

  defp reordered_valid_contract do
    %{
      "slices" => [
        %{
          "autonomy_ceiling" => "L1",
          "conflict_domains" => ["tasks_api"],
          "key" => "SLICE-001",
          "likely_files" => ["app/main.py", "tests/test_tasks.py"],
          "requirement_refs" => ["REQ-001"],
          "title" => "Add complete-a-task endpoint"
        }
      ],
      "schema_version" => "conveyor.plan@1",
      "requirements" => [
        %{
          "source_ref" => "plan.md#requirement-req-001",
          "status" => "covered",
          "risk" => "low",
          "text" => "New tasks expose completed:false by default.",
          "key" => "REQ-001"
        }
      ],
      "project" => %{"base_ref" => "main", "key" => "sample_tasks"},
      "verification_commands" => [
        %{"profile" => "verify", "argv" => ["pytest", "-q"], "key" => "pytest"}
      ],
      "non_goals" => ["Authentication", "Pagination"],
      "goal" => "Extend the sample tasks API so tasks can be marked complete.",
      "decisions" => [
        %{
          "key" => "DEC-001",
          "decision" => "Do not add authentication in Phase 1.",
          "rationale" => "Keep the tracer bullet focused on one low-risk API behavior."
        }
      ],
      "acceptance_criteria" => [
        %{
          "text" => "New tasks include completed:false.",
          "required_test_refs" => ["tests/test_tasks.py::test_create_defaults_completed_false"],
          "requirement_refs" => ["REQ-001"],
          "key" => "AC-001"
        }
      ]
    }
  end
end
