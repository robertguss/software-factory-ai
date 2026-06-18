defmodule Conveyor.ReviewerHealthTest do
  use Conveyor.DataCase, async: false

  alias Conveyor.Factory
  alias Conveyor.Factory.Review
  alias Conveyor.Factory.ReviewerHealth, as: ReviewerHealthRecord
  alias Conveyor.ReviewerHealth

  test "records passing reviewer health for the labeled fixture suite" do
    reviewer_profile_id = Ash.UUID.generate()

    health = ReviewerHealth.run_fixture_suite!(reviewer_profile_id)

    assert health.reviewer_profile_id == reviewer_profile_id
    assert health.rubric_version == "reviewer@1"
    assert health.fixture_suite_version == "reviewer-fixtures@1"
    assert health.passed
    assert health.failures == []
    assert :ok = ReviewerHealth.freshness_status(reviewer_profile_id, "reviewer@1")
  end

  test "rubber-stamp reviewer fails non-green dossier fixtures" do
    reviewer_profile_id = Ash.UUID.generate()

    reviewer = fn context ->
      %{
        "schema_version" => "conveyor.review@1",
        "run_spec_sha256" => context.run_spec_sha256,
        "dossier_sha256" => context.dossier_sha256,
        "reviewer" => %{
          "actor_id" => context.reviewer_session_id,
          "profile_id" => context.reviewer_profile_id
        },
        "rubric_version" => context.rubric_version,
        "decision" => "accepted",
        "recommendation" => "merge",
        "summary" => "Rubber-stamped fixture.",
        "findings" => [],
        "checks" => [
          %{
            "name" => context.fixture_key,
            "status" => "pass",
            "evidence_refs" => ["fixture://#{context.fixture_key}"],
            "summary" => "Rubber-stamped."
          }
        ]
      }
    end

    health = ReviewerHealth.run_fixture_suite!(reviewer_profile_id, reviewer: reviewer)

    refute health.passed
    failed_fixtures = MapSet.new(Enum.map(health.failures, & &1["fixture"]))
    assert MapSet.member?(failed_fixtures, "missing_acceptance_mapping")
    assert MapSet.member?(failed_fixtures, "protected_policy_edit")
    assert MapSet.member?(failed_fixtures, "malformed_evidence_refs")
    refute MapSet.member?(failed_fixtures, "complete_green_dossier")
  end

  test "freshness check blocks missing, failed, and stale reviewer health" do
    reviewer_profile_id = Ash.UUID.generate()
    review = %Review{reviewer_profile_id: reviewer_profile_id, rubric_version: "reviewer@1"}

    assert {:error, missing} = ReviewerHealth.require_fresh_review(review)
    assert missing["category"] == "missing_reviewer_health"

    failed_health =
      ReviewerHealth.run_fixture_suite!(reviewer_profile_id,
        reviewer: fn context ->
          context
          |> passing_review()
          |> Map.put("decision", "accepted")
          |> Map.put("recommendation", "merge")
        end
      )

    refute failed_health.passed
    assert {:error, failed} = ReviewerHealth.require_fresh_review(review)
    assert failed["category"] == "failed_reviewer_health"

    fresh_health = ReviewerHealth.run_fixture_suite!(reviewer_profile_id)
    assert fresh_health.passed
    assert :ok = ReviewerHealth.require_fresh_review(review)

    stale_now = DateTime.add(fresh_health.checked_at, 8 * 24 * 60 * 60, :second)
    assert {:error, stale} = ReviewerHealth.require_fresh_review(review, now: stale_now)
    assert stale["category"] == "stale_reviewer_health"
  end

  test "rerunning suite upserts health for the same profile rubric and suite" do
    reviewer_profile_id = Ash.UUID.generate()

    first = ReviewerHealth.run_fixture_suite!(reviewer_profile_id)
    second = ReviewerHealth.run_fixture_suite!(reviewer_profile_id)

    assert first.id == second.id
    assert length(Ash.read!(ReviewerHealthRecord, domain: Factory)) == 1
  end

  test "rerunning the fixture suite refreshes the freshness timestamp" do
    reviewer_profile_id = Ash.UUID.generate()

    first = ReviewerHealth.run_fixture_suite!(reviewer_profile_id)
    Process.sleep(2)
    second = ReviewerHealth.run_fixture_suite!(reviewer_profile_id)

    assert first.id == second.id
    # checked_at must advance on the update path so re-running restores freshness.
    assert DateTime.compare(second.checked_at, first.checked_at) == :gt
  end

  defp passing_review(context) do
    %{
      "schema_version" => "conveyor.review@1",
      "run_spec_sha256" => context.run_spec_sha256,
      "dossier_sha256" => context.dossier_sha256,
      "reviewer" => %{
        "actor_id" => context.reviewer_session_id,
        "profile_id" => context.reviewer_profile_id
      },
      "rubric_version" => context.rubric_version,
      "decision" => context.expected_decision,
      "recommendation" => context.expected_recommendation,
      "summary" => "Fixture expectation matched.",
      "findings" => [],
      "checks" => [
        %{
          "name" => context.fixture_key,
          "status" => "pass",
          "evidence_refs" => ["fixture://#{context.fixture_key}"],
          "summary" => "Fixture expectation matched."
        }
      ]
    }
  end
end
