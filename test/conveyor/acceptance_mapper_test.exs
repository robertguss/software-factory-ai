defmodule Conveyor.AcceptanceMapperTest do
  use ExUnit.Case, async: true

  alias Conveyor.Evidence.AcceptanceMapper

  test "maps every acceptance criterion to passed required test evidence" do
    result =
      AcceptanceMapper.map!(
        [
          criterion("AC-001", ["tests/tasks_test.exs::creates"]),
          criterion("AC-002", ["tests/tasks_test.exs::updates"])
        ],
        verification_result([
          test_result("tests/tasks_test.exs::creates", "passed"),
          test_result("tests/tasks_test.exs::updates", "passed")
        ])
      )

    assert result.status == :passed
    assert Enum.map(result.acceptance_results, & &1["evidence_status"]) == ["passed", "passed"]
    assert result.findings == []

    assert result.acceptance_results
           |> hd()
           |> Map.fetch!("evidence_refs") == ["test-result:tests/tasks_test.exs::creates"]
  end

  test "missing required test creates a blocking finding" do
    result =
      AcceptanceMapper.map!(
        [criterion("AC-001", ["tests/tasks_test.exs::missing"])],
        verification_result([])
      )

    assert result.status == :failed
    assert [%{"evidence_status" => "missing"}] = result.acceptance_results
    assert [finding] = result.findings
    assert finding["category"] == "missing_required_test"
    assert finding["acceptance_criterion_id"] == "AC-001"
    assert finding["test_ref"] == "tests/tasks_test.exs::missing"
  end

  test "skipped required test creates a blocking finding" do
    result =
      AcceptanceMapper.map!(
        [criterion("AC-001", ["tests/tasks_test.exs::skipped"])],
        verification_result([test_result("tests/tasks_test.exs::skipped", "skipped")])
      )

    assert result.status == :failed
    assert [%{"evidence_status" => "skipped"}] = result.acceptance_results
    assert [finding] = result.findings
    assert finding["category"] == "skipped_required_test"
  end

  test "failed required test maps the criterion to failed evidence" do
    result =
      AcceptanceMapper.map!(
        [criterion("AC-001", ["tests/tasks_test.exs::fails"])],
        verification_result([test_result("tests/tasks_test.exs::fails", "failed")])
      )

    assert result.status == :failed
    assert [%{"evidence_status" => "failed"}] = result.acceptance_results
    assert result.findings == []
  end

  defp criterion(id, required_test_refs) do
    %{
      "id" => id,
      "text" => "#{id} works",
      "kind" => "behavioral",
      "requirement_refs" => ["REQ-1"],
      "required_test_refs" => required_test_refs,
      "evidence_status" => "missing",
      "evidence_refs" => []
    }
  end

  defp verification_result(tests) do
    %{
      "suites" => [
        %{
          "commands" => [
            %{
              "attempts" => [
                %{"tests" => tests}
              ]
            }
          ]
        }
      ]
    }
  end

  defp test_result(id, status) do
    %{"id" => id, "name" => id, "status" => status}
  end
end
