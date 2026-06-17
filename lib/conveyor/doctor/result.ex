defmodule Conveyor.Doctor.Result do
  @moduledoc "Aggregate result returned by `Conveyor.Doctor`."

  alias Conveyor.Doctor.Finding

  @type status :: :passed | :failed
  @type t :: %__MODULE__{
          status: status(),
          findings: [Finding.t()],
          host_capabilities: map()
        }

  @enforce_keys [:status, :findings, :host_capabilities]
  defstruct [:status, :findings, :host_capabilities]
end
