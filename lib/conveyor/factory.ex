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
    resource Conveyor.Factory.Plan
    resource Conveyor.Factory.Requirement
    resource Conveyor.Factory.HumanDecision
    resource Conveyor.Factory.PlanAudit
    resource Conveyor.Factory.Epic
    resource Conveyor.Factory.Slice
    resource Conveyor.Factory.DiffPolicy
    resource Conveyor.Factory.ReviewPolicy
    resource Conveyor.Factory.AgentBrief
    resource Conveyor.Factory.ContractLock
    resource Conveyor.Factory.TestPack
    resource Conveyor.Factory.VerificationSuite
    resource Conveyor.Factory.TestPackCalibration
    resource Conveyor.Factory.RunSpec
  end
end
