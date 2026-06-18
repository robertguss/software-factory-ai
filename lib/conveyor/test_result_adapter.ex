defmodule Conveyor.TestResultAdapter do
  @moduledoc """
  Parses verification command output into stable test identities.
  """

  defmodule TestResult do
    @moduledoc false

    @type status :: :passed | :failed | :skipped
    @type t :: %__MODULE__{
            id: String.t(),
            name: String.t(),
            status: status(),
            message: String.t() | nil
          }

    @enforce_keys [:id, :name, :status]
    defstruct [:id, :name, :status, :message]
  end

  @callback parse(String.t(), keyword()) :: {:ok, [TestResult.t()]} | {:error, term()}

  @spec parse!(atom() | String.t(), String.t(), keyword()) :: [TestResult.t()]
  def parse!(format, output, opts \\ []) do
    case adapter(format).parse(output, opts) do
      {:ok, results} -> results
      {:error, reason} -> raise ArgumentError, "test result parse failed: #{inspect(reason)}"
    end
  end

  defp adapter(:stdout), do: Conveyor.TestResultAdapter.Stdout
  defp adapter(:json), do: Conveyor.TestResultAdapter.Json
  defp adapter(:tap), do: Conveyor.TestResultAdapter.Tap
  defp adapter(:junit), do: Conveyor.TestResultAdapter.JUnit
  defp adapter("stdout"), do: adapter(:stdout)
  defp adapter("json"), do: adapter(:json)
  defp adapter("tap"), do: adapter(:tap)
  defp adapter("junit"), do: adapter(:junit)
end
