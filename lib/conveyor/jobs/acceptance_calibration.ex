defmodule Conveyor.Jobs.AcceptanceCalibration do
  @moduledoc "Locked acceptance suite calibration worker skeleton."
  use Conveyor.Jobs.WorkerStub, queue: :gate

  def run!(run_spec, opts \\ []), do: Conveyor.AcceptanceCalibration.run!(run_spec, opts)
end
