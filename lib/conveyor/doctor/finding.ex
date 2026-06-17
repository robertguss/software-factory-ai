defmodule Conveyor.Doctor.Finding do
  @moduledoc "One actionable doctor finding."

  @type severity :: :failure | :warning
  @type t :: %__MODULE__{
          check: atom(),
          severity: severity(),
          message: String.t(),
          next_actions: [Conveyor.CLI.NextAction.t()]
        }

  @enforce_keys [:check, :severity, :message]
  defstruct [:check, :severity, :message, next_actions: []]
end
