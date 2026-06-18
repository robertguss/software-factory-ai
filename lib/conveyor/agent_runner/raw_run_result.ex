defmodule Conveyor.AgentRunner.RawRunResult do
  @moduledoc """
  Adapter-reported run output before independent Conveyor verification.
  """

  @type t :: %__MODULE__{
          summary: String.t(),
          messages: [map()],
          tool_calls: [map()],
          attempted_commands: [String.t()],
          diff_ref: String.t() | nil,
          metadata: map()
        }

  @enforce_keys [:summary]
  defstruct summary: nil,
            messages: [],
            tool_calls: [],
            attempted_commands: [],
            diff_ref: nil,
            metadata: %{}
end
