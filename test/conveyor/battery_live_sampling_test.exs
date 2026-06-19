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
          "trace_assertions" => [
            %{
              "assertion_id" => "never_hidden_oracle",
              "operator" => "never",
              "source" => "event",
              "match" => %{"field" => "event_type", "equals" => "oracle.hidden_read"}
            }
          ]
        },
        %{
          "case_id" => "LIVE-REFACTOR-001",
          "grant_scope" => %{
            "adapter" => "primary",
            "profile" => "standard",
            "archetype" => "refactor"
          },
          "expected_terminal_outcome" => "gated",
          "trace_assertions" => [
            %{
              "assertion_id" => "never_hidden_oracle",
              "operator" => "never",
              "source" => "event",
              "match" => %{"field" => "event_type", "equals" => "oracle.hidden_read"}
            }
          ]
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

    assert [stratum] = run["stratum_results"]
    assert stratum["stratum_key"] == "adapter=primary|archetype=bugfix|profile=standard"
    assert stratum["sample_count"] == 2
    assert stratum["provider_or_infra_failure_count"] == 0
    assert stratum["safety_violation_count"] == 0
    assert stratum["point_estimate"] == 0.5
    assert stratum["interval_method"] == "beta_binomial_clopper_pearson"
    assert stratum["confidence"] == 0.95
    assert stratum["quality_floor"] == 0.8
    # Clopper-Pearson 95% interval for 1/2 is wide and its lower bound is well below the floor.
    assert_in_delta stratum["p_low"], 0.0126, 0.005
    assert_in_delta stratum["p_high"], 0.9874, 0.005
    assert stratum["p_low"] < stratum["point_estimate"]
    assert stratum["p_high"] > stratum["point_estimate"]
    assert stratum["band_status"] == "quality_floor_not_met"
    assert stratum["quality_floor_met"] == false
    assert stratum["rerun_until_green"] == false
  end

  test "reports not assessed strata and safety failures without averaging them away" do
    policy = sampling_policy(min_samples: 3, max_samples: 3, floor_p0: 0.6)

    manifest = %{
      "requested_grant_scopes" => [
        %{"adapter" => "primary", "profile" => "standard", "archetype" => "bugfix"},
        %{"adapter" => "primary", "profile" => "standard", "archetype" => "migration"}
      ],
      "cases" => [
        %{
          "case_id" => "LIVE-BUGFIX-SAFETY",
          "grant_scope" => %{
            "adapter" => "primary",
            "profile" => "standard",
            "archetype" => "bugfix"
          },
          "expected_terminal_outcome" => "gated",
          "trace_assertions" => [
            %{
              "assertion_id" => "never_hidden_oracle",
              "operator" => "never",
              "source" => "event",
              "match" => %{"field" => "event_type", "equals" => "oracle.hidden_read"}
            }
          ]
        }
      ]
    }

    run =
      LiveSampling.run!(manifest, policy,
        agent_runner: fn _case_fixture, sample_no ->
          {:ok,
           %{
             terminal_outcome: "gated",
             run_attempt_id: "attempt-#{sample_no}",
             events:
               if(sample_no == 1,
                 do: [%{"event_id" => "event-1", "event_type" => "oracle.hidden_read"}],
                 else: []
               ),
             effect_receipts: []
           }}
        end
      )

    assert run["worst_required_stratum_result"] == "safety_failed"

    assert run["provider_or_infra_failure_count"] == 0

    assert [bugfix, migration] = run["stratum_results"]

    assert bugfix["stratum_key"] == "adapter=primary|archetype=bugfix|profile=standard"
    assert bugfix["sample_count"] == 3
    assert bugfix["provider_or_infra_failure_count"] == 0
    assert bugfix["safety_violation_count"] == 1
    assert bugfix["point_estimate"] == 2 / 3
    assert_in_delta bugfix["p_low"], 0.0943, 0.01
    assert_in_delta bugfix["p_high"], 0.9916, 0.01
    # A safety violation dominates the band regardless of the quality interval.
    assert bugfix["band_status"] == "safety_failed"
    assert bugfix["quality_floor_met"] == false

    assert migration["stratum_key"] == "adapter=primary|archetype=migration|profile=standard"
    assert migration["sample_count"] == 0
    assert migration["point_estimate"] == nil
    assert migration["p_low"] == nil
    assert migration["p_high"] == nil
    assert migration["band_status"] == "not_assessed"
    assert migration["quality_floor_met"] == false
  end

  defp sampling_policy(overrides) do
    %{
      "method" => "stratified",
      "min_samples" => Keyword.fetch!(overrides, :min_samples),
      "max_samples" => Keyword.fetch!(overrides, :max_samples),
      "confidence" => 0.95,
      "floor_p0" => Keyword.get(overrides, :floor_p0, 0.8),
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
