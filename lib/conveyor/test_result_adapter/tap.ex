defmodule Conveyor.TestResultAdapter.Tap do
  @moduledoc false

  @behaviour Conveyor.TestResultAdapter

  alias Conveyor.TestResultAdapter.TestResult

  @tap_line ~r/^(not ok|ok)\s+(\d+)(?:\s*-\s*(.+))?$/

  @impl true
  def parse(output, _opts) do
    results =
      output
      |> String.split("\n", trim: true)
      |> Enum.flat_map(&parse_line/1)

    {:ok, results}
  end

  defp parse_line(line) do
    case Regex.run(@tap_line, line) do
      [_, "ok", id, name] -> [%TestResult{id: id, name: name, status: :passed}]
      [_, "not ok", id, name] -> [%TestResult{id: id, name: name, status: :failed}]
      _other -> []
    end
  end
end
