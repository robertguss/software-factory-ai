defmodule Conveyor.TestResultAdapter.Json do
  @moduledoc false

  @behaviour Conveyor.TestResultAdapter

  alias Conveyor.TestResultAdapter.TestResult

  @impl true
  def parse(output, _opts) do
    with {:ok, decoded} <- Jason.decode(output),
         {:ok, tests} <- tests(decoded) do
      {:ok, Enum.map(tests, &test_result!/1)}
    end
  end

  defp tests(%{"tests" => tests}) when is_list(tests), do: {:ok, tests}
  defp tests(tests) when is_list(tests), do: {:ok, tests}
  defp tests(_decoded), do: {:error, :missing_tests}

  defp test_result!(test) do
    id = Map.get(test, "id") || Map.fetch!(test, "name")

    %TestResult{
      id: id,
      name: Map.get(test, "name", id),
      status: status!(Map.fetch!(test, "status")),
      message: Map.get(test, "message")
    }
  end

  defp status!("passed"), do: :passed
  defp status!("failed"), do: :failed
  defp status!("skipped"), do: :skipped
  defp status!(status) when status in [:passed, :failed, :skipped], do: status
end
