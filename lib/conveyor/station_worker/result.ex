defmodule Conveyor.StationWorker.Result do
  @moduledoc """
  Persistable worker lifecycle envelope.
  """

  @type t :: %__MODULE__{
          input: map(),
          output: map(),
          diagnostics: [map()],
          cache: map(),
          trace_context: map()
        }

  @enforce_keys [:input, :output, :diagnostics, :cache, :trace_context]
  defstruct [:input, :output, :diagnostics, :cache, :trace_context]
end
