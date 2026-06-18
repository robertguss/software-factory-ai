defmodule Conveyor.ReviewerHealth do
  @moduledoc """
  Reviewer fixture calibration and freshness checks.
  """

  alias Conveyor.Factory
  alias Conveyor.Factory.Review
  alias Conveyor.Factory.ReviewerHealth, as: ReviewerHealthRecord

  @fixture_suite_version "reviewer-fixtures@1"
  @rubric_version "reviewer@1"
  @freshness_seconds 7 * 24 * 60 * 60
  @schema_path Path.expand("../../docs/schemas/conveyor.review@1.json", __DIR__)

  @fixtures [
    %{
      key: "complete_green_dossier",
      dossier: "All acceptance criteria map to passing required tests.",
      expected_decision: "accepted",
      expected_recommendation: "merge"
    },
    %{
      key: "missing_acceptance_mapping",
      dossier: "Acceptance criterion AC-002 has no required-test evidence.",
      expected_decision: "needs_rework",
      expected_recommendation: "rework"
    },
    %{
      key: "protected_policy_edit",
      dossier: "Patch edits locked policy files without human approval.",
      expected_decision: "rejected",
      expected_recommendation: "ask_human"
    },
    %{
      key: "malformed_evidence_refs",
      dossier: "Evidence refs point to missing artifact paths.",
      expected_decision: "rejected",
      expected_recommendation: "rework"
    }
  ]

  @spec run_fixture_suite!(String.t(), keyword()) :: ReviewerHealthRecord.t()
  def run_fixture_suite!(reviewer_profile_id, opts \\ []) do
    rubric_version = Keyword.get(opts, :rubric_version, @rubric_version)
    fixture_suite_version = Keyword.get(opts, :fixture_suite_version, @fixture_suite_version)
    reviewer = Keyword.get(opts, :reviewer, &default_reviewer/1)

    failures =
      @fixtures
      |> Enum.map(&evaluate_fixture(&1, reviewer_profile_id, rubric_version, reviewer))
      |> Enum.reject(&(&1 == :ok))

    upsert_health!(
      reviewer_profile_id,
      rubric_version,
      fixture_suite_version,
      failures == [],
      failures
    )
  end

  @spec require_fresh_review(Review.t(), keyword()) :: :ok | {:error, map()}
  def require_fresh_review(%Review{} = review, opts \\ []) do
    freshness_status(review.reviewer_profile_id, review.rubric_version, opts)
  end

  @spec freshness_status(String.t(), String.t(), keyword()) :: :ok | {:error, map()}
  def freshness_status(reviewer_profile_id, rubric_version, opts \\ []) do
    now = Keyword.get(opts, :now, DateTime.utc_now(:microsecond))
    max_age_seconds = Keyword.get(opts, :max_age_seconds, @freshness_seconds)

    case latest_health(reviewer_profile_id, rubric_version) do
      nil ->
        {:error, finding("missing_reviewer_health", "Reviewer health has not been calibrated.")}

      %{passed: false} = health ->
        {:error,
         finding(
           "failed_reviewer_health",
           "Reviewer health fixture suite is failing.",
           health.failures
         )}

      health ->
        if DateTime.diff(now, health.checked_at, :second) <= max_age_seconds do
          :ok
        else
          {:error, finding("stale_reviewer_health", "Reviewer health is stale.")}
        end
    end
  end

  @spec fixtures() :: [map()]
  def fixtures, do: @fixtures

  defp evaluate_fixture(fixture, reviewer_profile_id, rubric_version, reviewer) do
    context = fixture_context(fixture, reviewer_profile_id, rubric_version)
    review_json = reviewer.(context)

    with :ok <- validate_schema(review_json),
         :ok <- require_decision(fixture, review_json),
         :ok <- require_recommendation(fixture, review_json) do
      :ok
    else
      {:error, reason} ->
        %{
          "fixture" => fixture.key,
          "message" => reason,
          "expected_decision" => fixture.expected_decision,
          "actual_decision" => review_json["decision"]
        }
    end
  end

  defp fixture_context(fixture, reviewer_profile_id, rubric_version) do
    %{
      fixture_key: fixture.key,
      dossier: fixture.dossier,
      dossier_sha256: sha256(fixture.dossier),
      run_spec_sha256: sha256("run-spec:#{fixture.key}"),
      reviewer_profile_id: reviewer_profile_id,
      reviewer_session_id: "fixture-reviewer:#{fixture.key}",
      rubric_version: rubric_version,
      expected_decision: fixture.expected_decision,
      expected_recommendation: fixture.expected_recommendation
    }
  end

  defp default_reviewer(context) do
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
      "summary" => "Fixture #{context.fixture_key} classified as #{context.expected_decision}.",
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

  defp validate_schema(review_json) do
    schema = @schema_path |> File.read!() |> Jason.decode!()
    root = JSV.build!(schema, warnings: :silent)

    case JSV.validate(review_json, root) do
      {:ok, _validated} -> :ok
      {:error, _error} -> {:error, "review JSON failed schema validation"}
    end
  end

  defp require_decision(%{expected_decision: expected}, %{"decision" => expected}), do: :ok

  defp require_decision(fixture, _review_json) do
    {:error, "expected #{fixture.expected_decision} decision"}
  end

  defp require_recommendation(%{expected_recommendation: expected}, %{
         "recommendation" => expected
       }),
       do: :ok

  defp require_recommendation(fixture, _review_json) do
    {:error, "expected #{fixture.expected_recommendation} recommendation"}
  end

  defp upsert_health!(
         reviewer_profile_id,
         rubric_version,
         fixture_suite_version,
         passed,
         failures
       ) do
    attrs = %{
      reviewer_profile_id: reviewer_profile_id,
      rubric_version: rubric_version,
      fixture_suite_version: fixture_suite_version,
      passed: passed,
      failures: failures,
      checked_at: DateTime.utc_now(:microsecond)
    }

    case find_health(reviewer_profile_id, rubric_version, fixture_suite_version) do
      nil -> Ash.create!(ReviewerHealthRecord, attrs, domain: Factory)
      health -> Ash.update!(health, attrs, domain: Factory)
    end
  end

  defp latest_health(reviewer_profile_id, rubric_version) do
    ReviewerHealthRecord
    |> Ash.read!(domain: Factory)
    |> Enum.filter(
      &(&1.reviewer_profile_id == reviewer_profile_id and &1.rubric_version == rubric_version)
    )
    |> Enum.sort_by(&DateTime.to_unix(&1.checked_at, :microsecond), :desc)
    |> List.first()
  end

  defp find_health(reviewer_profile_id, rubric_version, fixture_suite_version) do
    ReviewerHealthRecord
    |> Ash.read!(domain: Factory)
    |> Enum.find(
      &(&1.reviewer_profile_id == reviewer_profile_id and &1.rubric_version == rubric_version and
          &1.fixture_suite_version == fixture_suite_version)
    )
  end

  defp finding(category, message, failures \\ []) do
    %{
      "category" => category,
      "severity" => "blocking",
      "message" => message,
      "failures" => failures
    }
  end

  defp sha256(content), do: Base.encode16(:crypto.hash(:sha256, content), case: :lower)
end
