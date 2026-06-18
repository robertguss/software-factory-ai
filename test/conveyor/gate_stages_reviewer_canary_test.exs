defmodule Conveyor.GateStagesReviewerCanaryTest do
  use ExUnit.Case, async: true

  alias Conveyor.Factory.GateHealth
  alias Conveyor.Factory.Review
  alias Conveyor.Gate
  alias Conveyor.Gate.Stages.CanaryFreshness
  alias Conveyor.Gate.Stages.ReviewerAggregation

  @now ~U[2026-06-18 10:00:00Z]
  @reviewer_profile_id "00000000-0000-0000-0000-000000000001"

  test "reviewer aggregation passes with required accepted reviews and fresh health" do
    result =
      ReviewerAggregation.run(%{
        required_review_kinds: [:general, :security],
        dossier_sha256: "dossier-sha",
        now: @now,
        reviews: [
          review(:general),
          review(:security)
        ],
        reviewer_health: [
          health(@reviewer_profile_id, "reviewer@1", checked_at: @now),
          health("00000000-0000-0000-0000-000000000002", "reviewer@1", checked_at: @now)
        ]
      })

    assert result.status == :passed
    assert result.findings == []
  end

  test "reviewer aggregation fails missing reviews dossier mismatch bad decision and stale health" do
    stale = DateTime.add(@now, -10 * 24 * 60 * 60, :second)

    result =
      ReviewerAggregation.run(%{
        required_review_kinds: [:general, :security],
        dossier_sha256: "dossier-sha",
        now: @now,
        reviews: [%{review(:general) | dossier_sha256: "other", decision: :needs_rework}],
        reviewer_health: [health(@reviewer_profile_id, "reviewer@1", checked_at: stale)]
      })

    assert result.status == :failed
    categories = Enum.map(result.findings, & &1["category"])
    assert "missing_required_review" in categories
    assert "review_dossier_mismatch" in categories
    assert "review_decision_not_accepted" in categories
    assert "stale_reviewer_health" in categories
  end

  test "canary freshness passes with a green fresh record for the current key" do
    context = canary_context()
    key = CanaryFreshness.freshness_key_sha256(context)

    result =
      context
      |> Map.put(:gate_health, gate_health(key, checked_at: @now))
      |> CanaryFreshness.run()

    assert result.status == :passed
    assert result.findings == []
  end

  test "canary freshness fails stale mismatched or non-green records" do
    context = canary_context()
    key = CanaryFreshness.freshness_key_sha256(context)
    old = DateTime.add(@now, -2 * 24 * 60 * 60, :second)

    stale =
      context
      |> Map.put(:gate_health, gate_health(key, checked_at: old))
      |> CanaryFreshness.run()

    assert stale.status == :failed
    assert Enum.any?(stale.findings, &(&1["category"] == "stale_canary"))

    failed =
      context
      |> Map.put(:gate_health, gate_health(key, passed: false, checked_at: @now))
      |> CanaryFreshness.run()

    assert failed.status == :failed
    assert Enum.any?(failed.findings, &(&1["category"] == "stale_canary"))

    mismatched =
      context
      |> Map.put(:gate_health, gate_health("sha256:mismatch", checked_at: @now))
      |> CanaryFreshness.run()

    assert mismatched.status == :failed
    assert Enum.any?(mismatched.findings, &(&1["category"] == "stale_canary"))
  end

  test "reviewer aggregation and canary freshness compose through the gate framework" do
    context = canary_context()
    key = CanaryFreshness.freshness_key_sha256(context)

    result =
      context
      |> Map.merge(%{
        required_review_kinds: [:general],
        dossier_sha256: "dossier-sha",
        reviews: [review(:general)],
        reviewer_health: [health(@reviewer_profile_id, "reviewer@1", checked_at: @now)],
        gate_health: gate_health(key, checked_at: @now)
      })
      |> Gate.run!([
        %{key: "reviewer_aggregation", module: ReviewerAggregation},
        %{key: "canary_freshness", module: CanaryFreshness}
      ])

    assert result.passed?
    assert Enum.map(result.stages, & &1.status) == [:passed, :passed]
  end

  defp review(kind) do
    %Review{
      id: "review-#{kind}",
      review_kind: kind,
      reviewer_profile_id: @reviewer_profile_id,
      rubric_version: "reviewer@1",
      dossier_sha256: "dossier-sha",
      decision: :accepted,
      recommendation: :merge,
      findings: [],
      checks: []
    }
  end

  defp health(profile_id, rubric_version, opts) do
    %{
      reviewer_profile_id: profile_id,
      rubric_version: rubric_version,
      passed: Keyword.get(opts, :passed, true),
      checked_at: Keyword.fetch!(opts, :checked_at),
      failures: []
    }
  end

  defp canary_context do
    %{
      now: @now,
      gate_health_max_age_seconds: 24 * 60 * 60,
      gate_code_sha256: "sha256:gate",
      policy_sha256: "sha256:policy",
      test_pack_sha256: "sha256:test-pack",
      container_image_digest: "sha256:image",
      code_quality_profile_sha256: "sha256:quality",
      canary_suite_version: "canary@1",
      runcheck_schema_version: "conveyor.run_bundle@1",
      contract_lock_sha256: "sha256:contract"
    }
  end

  defp gate_health(key, opts) do
    %GateHealth{
      id: "gate-health-1",
      freshness_key_sha256: key,
      gate_version: "gate@1",
      gate_code_sha256: "sha256:gate",
      policy_sha256: "sha256:policy",
      test_pack_sha256: "sha256:test-pack",
      container_image_digest: "sha256:image",
      code_quality_profile_sha256: "sha256:quality",
      canary_suite_version: "canary@1",
      runcheck_schema_version: "conveyor.run_bundle@1",
      last_run_ref: "gate-canaries/latest.json",
      passed: Keyword.get(opts, :passed, true),
      false_negative_count: Keyword.get(opts, :false_negative_count, 0),
      checked_at: Keyword.fetch!(opts, :checked_at)
    }
  end
end
