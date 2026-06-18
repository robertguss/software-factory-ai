defmodule Conveyor.TestResultAdapter.Stdout do
  @moduledoc false

  @behaviour Conveyor.TestResultAdapter

  alias Conveyor.TestResultAdapter.TestResult

  @impl true
  def parse(output, opts) do
    key = Keyword.get(opts, :test_id, "stdout")
    exit_code = Keyword.get(opts, :exit_code, 0)

    status = if exit_code == 0, do: :passed, else: :failed
    message = if status == :failed, do: output, else: nil

    {:ok, [%TestResult{id: key, name: key, status: status, message: message}]}
  end
end
