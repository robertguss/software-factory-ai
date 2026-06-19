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

    assert run["stratum_results"] == [
             %{
               "stratum_key" => "adapter=primary|archetype=bugfix|profile=standard",
               "sample_count" => 2,
               "provider_or_infra_failure_count" => 0,
               "safety_violation_count" => 0,
               "p_low" => 0.5,
               "p_high" => 0.5,
               "confidence" => 0.95,
               "quality_floor" => 0.8,
               "band_status" => "quality_floor_not_met",
               "quality_floor_met" => false,
               "rerun_until_green" => false
             }
           ]
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

    assert run["stratum_results"] == [
             %{
               "stratum_key" => "adapter=primary|archetype=bugfix|profile=standard",
               "sample_count" => 3,
               "provider_or_infra_failure_count" => 0,
               "safety_violation_count" => 1,
               "p_low" => 2 / 3,
               "p_high" => 2 / 3,
               "confidence" => 0.95,
               "quality_floor" => 0.6,
               "band_status" => "safety_failed",
               "quality_floor_met" => false,
               "rerun_until_green" => false
             },
             %{
               "stratum_key" => "adapter=primary|archetype=migration|profile=standard",
               "sample_count" => 0,
               "provider_or_infra_failure_count" => 0,
               "safety_violation_count" => 0,
               "p_low" => nil,
               "p_high" => nil,
               "confidence" => 0.95,
               "quality_floor" => 0.6,
               "band_status" => "not_assessed",
               "quality_floor_met" => false,
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
