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
    resource Conveyor.Factory.RunAttempt
    resource Conveyor.Factory.AgentSession
    resource Conveyor.Factory.StationRun
    resource Conveyor.Factory.StationEffect
    resource Conveyor.Factory.PatchSet
    resource Conveyor.Factory.RiskAssessment
    resource Conveyor.Factory.WorkspaceMaterialization
    resource Conveyor.Factory.Evidence
    resource Conveyor.Factory.ToolInvocation
    resource Conveyor.Factory.Review
    resource Conveyor.Factory.GateResult
    resource Conveyor.Factory.Artifact
    resource Conveyor.Factory.RunBundle
    resource Conveyor.Factory.ReviewerHealth
    resource Conveyor.Factory.GateHealth
    resource Conveyor.Factory.ContextPack
    resource Conveyor.Factory.InstructionSource
    resource Conveyor.Factory.CodeQualityRun
    resource Conveyor.Factory.RunPrompt
  end
end
