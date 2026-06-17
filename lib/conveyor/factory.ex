defmodule Conveyor.Factory do
  @moduledoc """
  Ash domain for Conveyor's factory control-plane resources.
  """

  use Ash.Domain,
    otp_app: :conveyor

  resources do
    resource Conveyor.Factory.Project
    resource Conveyor.Factory.ToolchainProfile
    resource Conveyor.Factory.CacheMount
  end
end
