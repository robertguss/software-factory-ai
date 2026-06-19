defmodule Conveyor.ContractCriticIndependenceTest do
  use ExUnit.Case, async: true

  alias Conveyor.ContractCritic.IndependenceProfile

  test "records a challenge role independence profile" do
    profile =
      IndependenceProfile.record!(%{
        challenge_role: "security_critic",
        profile: "model_diverse",
        evidence_refs: ["model:critic-b", "context:separated"]
      })

    assert profile["schema_version"] == "conveyor.independence_profile@1"
    assert profile["challenge_role"] == "security_critic"
    assert profile["profile"] == "model_diverse"
    assert profile["independence_profile_digest"] =~ ~r/^sha256:[0-9a-f]{64}$/
  end

  test "high-risk changes require model-diverse or human/deterministic critical lens" do
    weak = [
      IndependenceProfile.record!(%{
        challenge_role: "security_critic",
        profile: "context_separated",
        evidence_refs: ["context:separated"]
      })
    ]

    assert {:error, findings} =
             IndependenceProfile.enforce!(%{
               change_classes: ["security", "public_compat"],
               profiles: weak
             })

    assert [%{rule_key: "critic.independence_insufficient", severity: :blocking}] = findings

    strong = [
      IndependenceProfile.record!(%{
        challenge_role: "security_critic",
        profile: "human_or_deterministic",
        evidence_refs: ["human:principal"]
      })
    ]

    assert :ok =
             IndependenceProfile.enforce!(%{
               change_classes: ["security"],
               profiles: strong
             })
  end
end
