defmodule Conveyor.TestResultAdapterTest do
  use ExUnit.Case, async: true

  alias Conveyor.TestResultAdapter

  test "parses stdout into a synthetic command identity" do
    assert [result] = TestResultAdapter.parse!(:stdout, "ok\n", test_id: "pytest", exit_code: 0)
    assert result.id == "pytest"
    assert result.status == :passed

    assert [failed] = TestResultAdapter.parse!(:stdout, "boom\n", test_id: "pytest", exit_code: 1)
    assert failed.status == :failed
    assert failed.message == "boom\n"
  end

  test "parses JSON test results" do
    output =
      Jason.encode!(%{
        tests: [
          %{id: "test-a", name: "passes", status: "passed"},
          %{id: "test-b", name: "fails", status: "failed", message: "assertion"}
        ]
      })

    assert [passed, failed] = TestResultAdapter.parse!(:json, output)
    assert passed.id == "test-a"
    assert passed.status == :passed
    assert failed.id == "test-b"
    assert failed.status == :failed
    assert failed.message == "assertion"
  end

  test "parses TAP output" do
    output = """
    TAP version 13
    ok 1 - creates task
    not ok 2 - deletes task
    """

    assert [passed, failed] = TestResultAdapter.parse!(:tap, output)
    assert passed.id == "1"
    assert passed.name == "creates task"
    assert passed.status == :passed
    assert failed.id == "2"
    assert failed.status == :failed
  end

  test "parses JUnit testcase output" do
    output = """
    <testsuite>
      <testcase classname="TasksTest" name="creates task" />
      <testcase classname="TasksTest" name="deletes task"><failure message="nope" /></testcase>
    </testsuite>
    """

    results = TestResultAdapter.parse!(:junit, output)
    passed = Enum.find(results, &(&1.id == "TasksTest.creates task"))
    failed = Enum.find(results, &(&1.id == "TasksTest.deletes task"))

    assert passed.id == "TasksTest.creates task"
    assert passed.status == :passed
    assert failed.id == "TasksTest.deletes task"
    assert failed.status == :failed
    assert failed.message =~ "failure"
  end
end
