defmodule Conveyor.StationWorker.Context do
  @moduledoc """
  Context passed to generic station-worker role modules.
  """

  @type t :: %__MODULE__{cache: map(), trace_context: map()}

  @enforce_keys [:cache, :trace_context]
  defstruct [:cache, :trace_context]
end
