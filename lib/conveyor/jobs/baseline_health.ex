defmodule Conveyor.Jobs.BaselineHealth do
  @moduledoc "Clean-checkout baseline health worker skeleton."
  use Conveyor.Jobs.WorkerStub, queue: :gate

  def run!(run_spec, opts \\ []), do: Conveyor.BaselineHealth.run!(run_spec, opts)
end
