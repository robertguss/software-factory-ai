defmodule Conveyor.BatteryLiveSamplingTest do
  use ExUnit.Case, async: true

  alias Conveyor.Battery.LiveSampling
  alias Conveyor.Battery.SamplingPolicy

  test "executes predeclared samples only for requested grant-scope strata" do
    policy = sampling_policy(min_samples: 2, max_samples: 2)

    manifest = %{
      "requested_grant_scopes" => [
        %{"adapter" => "primary", "profile" => "standard", "archetype" => "bugfix"}
      ],
      "cases" => [
        %{
          "case_id" => "LIVE-BUGFIX-001",
          "grant_scope" => %{
            "adapter" => "primary",
            "profile" => "standard",
            "archetype" => "bugfix"
          },
          "expected_terminal_outcome" => "gated",
          "trace_assertions" => []
        },
        %{
          "case_id" => "LIVE-REFACTOR-001",
          "grant_scope" => %{
            "adapter" => "primary",
            "profile" => "standard",
            "archetype" => "refactor"
          },
          "expected_terminal_outcome" => "gated",
          "trace_assertions" => []
        }
      ]
    }

    run =
      LiveSampling.run!(manifest, policy,
        agent_runner: fn case_fixture, sample_no ->
          send(self(), {:sample, case_fixture["case_id"], sample_no})

          {:ok,
           %{
             terminal_outcome: if(sample_no == 1, do: "needs_rework", else: "gated"),
             run_attempt_id: "attempt-#{case_fixture["case_id"]}-#{sample_no}",
             events: [],
             effect_receipts: []
           }}
        end
      )

    assert_received {:sample, "LIVE-BUGFIX-001", 1}
    assert_received {:sample, "LIVE-BUGFIX-001", 2}
    refute_received {:sample, "LIVE-REFACTOR-001", _sample_no}

    assert run["schema_version"] == "conveyor.live_sample_run@1"
    assert run["sampling_policy_digest"] == policy["policy_digest"]

    assert Enum.map(run["sample_results"], & &1.battery_case_id) == [
             "LIVE-BUGFIX-001",
             "LIVE-BUGFIX-001"
           ]

    assert run["stratum_results"] == [
             %{
               "stratum_key" => "adapter=primary|archetype=bugfix|profile=standard",
               "sample_count" => 2,
               "miss_count" => 1,
               "band_status" => "miss_observed",
               "rerun_until_green" => false
             }
           ]
  end

  defp sampling_policy(overrides) do
    %{
      "method" => "stratified",
      "min_samples" => Keyword.fetch!(overrides, :min_samples),
      "max_samples" => Keyword.fetch!(overrides, :max_samples),
      "confidence" => 0.95,
      "floor_p0" => 0.8,
      "stopping_rule" => "fixed-max-or-release-fail",
      "sampling_unit" => "repository_case_cluster",
      "cluster_key" => "repo:case-cluster",
      "max_samples_per_cluster" => 2,
      "strata" => ["adapter", "profile", "archetype"],
      "sequential_validity" => "predeclared"
    }
    |> SamplingPolicy.predeclare!()
  end
end
