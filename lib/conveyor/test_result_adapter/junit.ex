defmodule Conveyor.TestResultAdapter.JUnit do
  @moduledoc false

  @behaviour Conveyor.TestResultAdapter

  alias Conveyor.TestResultAdapter.TestResult

  @paired_testcase ~r/<testcase\b((?:(?!\/>).)*?)>(.*?)<\/testcase>/s
  @self_closing_testcase ~r/<testcase\b([^>]*)\/>/
  @attr ~r/([A-Za-z_:][-A-Za-z0-9_:.]*)="([^"]*)"/

  @impl true
  def parse(output, _opts) do
    results =
      paired_results(output) ++ self_closing_results(output)

    {:ok, results}
  end

  defp paired_results(output) do
    @paired_testcase
    |> Regex.scan(output)
    |> Enum.map(fn [_full, attrs, body] -> testcase_result!(attrs, body) end)
  end

  defp self_closing_results(output) do
    @self_closing_testcase
    |> Regex.scan(output)
    |> Enum.map(fn [_full, attrs] -> testcase_result!(attrs, "") end)
  end

  defp testcase_result!(attrs, body) do
    attrs
    |> attrs()
    |> result(body)
  end

  defp attrs(attrs) do
    @attr
    |> Regex.scan(attrs)
    |> Map.new(fn [_full, key, value] -> {key, value} end)
  end

  defp result(attrs, body) do
    name = Map.fetch!(attrs, "name")
    class = Map.get(attrs, "classname")
    id = if class in [nil, ""], do: name, else: "#{class}.#{name}"

    status =
      cond do
        String.contains?(body, "<failure") or String.contains?(body, "<error") -> :failed
        String.contains?(body, "<skipped") -> :skipped
        true -> :passed
      end

    %TestResult{id: id, name: name, status: status, message: failure_message(body)}
  end

  defp failure_message(body) do
    if String.contains?(body, "<failure") or String.contains?(body, "<error"), do: body
  end
end
