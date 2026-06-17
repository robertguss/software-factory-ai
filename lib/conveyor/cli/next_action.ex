defmodule Conveyor.CLI.NextAction do
  @moduledoc "Actionable remediation hint attached to blocking findings."

  @type t :: %__MODULE__{
          label: String.t(),
          command: String.t()
        }

  @enforce_keys [:label, :command]
  defstruct [:label, :command]
end
