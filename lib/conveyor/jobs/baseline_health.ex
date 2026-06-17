defmodule Conveyor.Jobs.BaselineHealth do
  @moduledoc "Clean-checkout baseline health worker skeleton."
  use Conveyor.Jobs.WorkerStub, queue: :gate
end
