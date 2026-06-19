defmodule Conveyor.BatterySecondaryConfirmationTest do
  use ExUnit.Case, async: true

  alias Conveyor.Battery.SamplingPolicy
  alias Conveyor.Battery.SecondaryConfirmation

  test "secondary adapter outage is recorded without invalidating the deterministic build" do
    policy = sampling_policy()

    manifest = %{
      "primary_adapter_id" => "adapter:primary",
      "secondary_adapter_id" => "adapter:secondary-materially-different",
      "representative_case_ids" => ["LIVE-BUGFIX-001"],
      "cases" => [
        %{
          "case_id" => "LIVE-BUGFIX-001",
          "grant_scope" => %{"adapter" => "primary", "archetype" => "bugfix"},
          "expected_terminal_outcome" => "gated",
          "trace_assertions" => []
        },
        %{
          "case_id" => "LIVE-REFACTOR-001",
          "grant_scope" => %{"adapter" => "primary", "archetype" => "refactor"},
          "expected_terminal_outcome" => "gated",
          "trace_assertions" => []
        }
      ]
    }

    report =
      SecondaryConfirmation.run!(manifest, policy,
        agent_runner: fn case_fixture, sample_no ->
          send(self(), {:secondary_sample, case_fixture["case_id"], sample_no})
          {:error, :secondary_adapter_unavailable}
        end
      )

    assert_received {:secondary_sample, "LIVE-BUGFIX-001", 1}
    refute_received {:secondary_sample, "LIVE-REFACTOR-001", _sample_no}

    assert report["schema_version"] == "conveyor.secondary_live_confirmation@1"
    assert report["confirmation_role"] == "non_gating_confirmation"
    assert report["selected_case_ids"] == ["LIVE-BUGFIX-001"]
    assert report["status"] == "secondary_unavailable"
    assert report["invalidates_core_build"] == false
    assert report["core_build_oracle"] == "deterministic_primary_unchanged"
    assert report["provider_or_infra_failure_count"] == 1
  end

  test "secondary confirmation requires a materially different adapter id" do
    policy = sampling_policy()

    manifest = %{
      "primary_adapter_id" => "adapter:primary",
      "secondary_adapter_id" => "adapter:primary",
      "representative_case_ids" => [],
      "cases" => []
    }

    assert_raise ArgumentError, ~r/secondary adapter must differ from primary adapter/, fn ->
      SecondaryConfirmation.run!(manifest, policy,
        agent_runner: fn _case_fixture, _sample_no -> {:ok, %{}} end
      )
    end
  end

  defp sampling_policy do
    %{
      "method" => "stratified",
      "min_samples" => 1,
      "max_samples" => 1,
      "confidence" => 0.95,
      "floor_p0" => 0.8,
      "stopping_rule" => "fixed-max-or-release-fail",
      "sampling_unit" => "repository_case_cluster",
      "cluster_key" => "repo:case-cluster",
      "max_samples_per_cluster" => 1,
      "strata" => ["adapter", "archetype"],
      "sequential_validity" => "predeclared"
    }
    |> SamplingPolicy.predeclare!()
  end
end
