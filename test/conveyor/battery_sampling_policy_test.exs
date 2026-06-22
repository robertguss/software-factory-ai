defmodule Conveyor.BatterySamplingPolicyTest do
  use ExUnit.Case, async: true

  alias Conveyor.Battery.SamplingPolicy

  @policy_path "test/fixtures/phase-1.5/p15-b1/sampling-policy.json"

  test "predeclare returns a content-addressed policy digest independent of map key order" do
    attrs = %{
      "method" => "stratified",
      "min_samples" => 4,
      "max_samples" => 20,
      "confidence" => 0.95,
      "floor_p0" => 0.8,
      "stopping_rule" => "fixed-max-or-release-fail",
      "sampling_unit" => "repository_case_cluster",
      "cluster_key" => "repo:case-cluster",
      "max_samples_per_cluster" => 2,
      "strata" => ["repo", "archetype", "criticality"],
      "sequential_validity" => "predeclared"
    }

    reversed_attrs = attrs |> Enum.reverse() |> Map.new()

    policy = SamplingPolicy.predeclare!(attrs)
    same_policy = SamplingPolicy.predeclare!(reversed_attrs)

    assert policy["schema_version"] == "conveyor.sampling_policy@1"
    assert policy["policy_digest"] =~ ~r/^sha256:[0-9a-f]{64}$/
    assert same_policy["policy_digest"] == policy["policy_digest"]
  end

  test "threshold or stopping rule changes create a different policy digest" do
    baseline =
      SamplingPolicy.predeclare!(%{
        "method" => "sequential",
        "min_samples" => 3,
        "max_samples" => 12,
        "confidence" => 0.95,
        "floor_p0" => 0.7,
        "stopping_rule" => "confidence-sequence-v1",
        "sampling_unit" => "repository_case_cluster",
        "cluster_key" => "repo:case-family",
        "max_samples_per_cluster" => 3,
        "strata" => ["archetype", "risk", "language_toolchain"],
        "sequential_validity" => "predeclared"
      })

    changed_threshold = SamplingPolicy.predeclare!(%{baseline | "floor_p0" => 0.75})
    changed_stop_rule = SamplingPolicy.predeclare!(%{baseline | "stopping_rule" => "fixed-n-v1"})

    refute changed_threshold["policy_digest"] == baseline["policy_digest"]
    refute changed_stop_rule["policy_digest"] == baseline["policy_digest"]
  end

  test "Phase 1.5 policy artifact is predeclared with a self-consistent digest" do
    policy = @policy_path |> File.read!() |> Jason.decode!()

    assert policy["schema_version"] == "conveyor.sampling_policy@1"
    assert policy["sequential_validity"] == "predeclared"
    assert SamplingPolicy.digest(policy) == policy["policy_digest"]
  end
end
