defmodule Conveyor.TestResultAdapter.TapTest do
  use ExUnit.Case, async: true

  alias Conveyor.TestResultAdapter.Tap

  test "parses bare ok/not-ok lines that have no description" do
    output = """
    ok 1
    not ok 2
    ok 3 - documented case
    """

    {:ok, results} = Tap.parse(output, [])

    assert length(results) == 3
    assert Enum.map(results, & &1.id) == ["1", "2", "3"]
    assert Enum.map(results, & &1.status) == [:passed, :failed, :passed]
    # bare lines fall back to the id for the name
    assert Enum.map(results, & &1.name) == ["1", "2", "documented case"]
  end
end
