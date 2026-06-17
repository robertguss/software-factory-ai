defmodule Conveyor.Jobs.RecordEvidence do
  @moduledoc "Independent evidence recording worker skeleton."
  use Conveyor.Jobs.WorkerStub, queue: :gate
end
