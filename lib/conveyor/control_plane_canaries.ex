defmodule Conveyor.ControlPlaneCanaries do
  @moduledoc """
  Required P15-A4 control-plane canary names.
  """

  @required_keys [
    "gc-cannot-erase-active-authority",
    "erased-incomparable",
    "stop-blocks-new-effects",
    "reservation-required-before-spend",
    "runaway-opens-circuit",
    "adapter-health-narrows-authority"
  ]

  def required_keys, do: @required_keys
end
