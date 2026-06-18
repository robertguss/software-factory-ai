defmodule Conveyor.Gate.Stages.ReviewerAggregation do
  @moduledoc """
  Gate stage 13: aggregates required independent reviews and reviewer health.
  """

  @behaviour Conveyor.Gate.Stage

  alias Conveyor.Gate.StageResult
  alias Conveyor.ReviewerHealth

  @freshness_seconds 7 * 24 * 60 * 60

  @impl true
  def run(context, _opts \\ []) do
    required_kinds = required_review_kinds(context)
    reviews = value(context, :reviews) || []
    health_records = value(context, :reviewer_health) || []
    findings = findings(required_kinds, reviews, health_records, context)

    %StageResult{
      key: "reviewer_aggregation",
      status: status(findings),
      required?: true,
      findings: findings,
      evidence_refs: evidence_refs(reviews),
      input_digests: %{
        "required_review_kinds" => Enum.map(required_kinds, &Atom.to_string/1),
        "review_count" => length(reviews),
        "dossier_sha256" => value(context, :dossier_sha256)
      }
    }
  end

  defp findings(required_kinds, reviews, health_records, context) do
    required_kinds
    |> Enum.flat_map(&review_kind_findings(&1, reviews, health_records, context))
  end

  defp review_kind_findings(kind, reviews, health_records, context) do
    case Enum.find(reviews, &(normalize_kind(value(&1, :review_kind)) == kind)) do
      nil -> [finding("missing_required_review", "Required review kind is missing.", kind)]
      review -> review_findings(review, health_records, context)
    end
  end

  defp review_findings(review, health_records, context) do
    []
    |> Kernel.++(schema_findings(review))
    |> Kernel.++(dossier_findings(review, value(context, :dossier_sha256)))
    |> Kernel.++(
      decision_findings(review, value(context, :required_review_decision) || :accepted)
    )
    |> Kernel.++(health_findings(review, health_records, context))
  end

  defp schema_findings(review) do
    required = [:review_kind, :reviewer_profile_id, :rubric_version, :dossier_sha256, :decision]

    required
    |> Enum.reject(&(value(review, &1) not in [nil, ""]))
    |> Enum.map(fn field ->
      finding(
        "review_schema_validation_failed",
        "Review is missing a required schema field.",
        value(review, :review_kind),
        %{"field" => Atom.to_string(field)}
      )
    end)
  end

  defp dossier_findings(_review, nil), do: []

  defp dossier_findings(review, dossier_sha256) do
    if value(review, :dossier_sha256) == dossier_sha256 do
      []
    else
      [
        finding(
          "review_dossier_mismatch",
          "Review was not evaluated against the gate dossier digest.",
          value(review, :review_kind)
        )
      ]
    end
  end

  defp decision_findings(review, required_decision) do
    if normalize_kind(value(review, :decision)) == normalize_kind(required_decision) do
      []
    else
      [
        finding(
          "review_decision_not_accepted",
          "Required review did not meet the configured decision threshold.",
          value(review, :review_kind),
          %{"decision" => to_string(value(review, :decision))}
        )
      ]
    end
  end

  defp health_findings(review, health_records, context) do
    if match?(%Conveyor.Factory.Review{}, review) and health_records == [] do
      case ReviewerHealth.require_fresh_review(review,
             now: value(context, :now) || DateTime.utc_now(:microsecond),
             max_age_seconds:
               value(context, :reviewer_health_max_age_seconds) || @freshness_seconds
           ) do
        :ok -> []
        {:error, finding} -> [finding]
      end
    else
      manual_health_findings(review, health_records, context)
    end
  end

  defp manual_health_findings(review, health_records, context) do
    reviewer_profile_id = value(review, :reviewer_profile_id)
    rubric_version = value(review, :rubric_version)

    health =
      health_records
      |> Enum.filter(&(value(&1, :reviewer_profile_id) == reviewer_profile_id))
      |> Enum.filter(&(value(&1, :rubric_version) == rubric_version))
      |> Enum.sort_by(&timestamp(value(&1, :checked_at)), :desc)
      |> List.first()

    cond do
      is_nil(health) ->
        [
          finding(
            "missing_reviewer_health",
            "Reviewer health has not been calibrated.",
            value(review, :review_kind)
          )
        ]

      value(health, :passed) != true ->
        [
          finding(
            "failed_reviewer_health",
            "Reviewer health fixture suite is failing.",
            value(review, :review_kind)
          )
        ]

      stale?(value(health, :checked_at), context, :reviewer_health_max_age_seconds) ->
        [
          finding(
            "stale_reviewer_health",
            "Reviewer health is stale.",
            value(review, :review_kind)
          )
        ]

      true ->
        []
    end
  end

  defp required_review_kinds(context) do
    kinds =
      value(context, :required_review_kinds) ||
        value(value(context, :risk_assessment), :required_review_kinds) || [:general]

    kinds |> List.wrap() |> Enum.map(&normalize_kind/1) |> Enum.uniq()
  end

  defp stale?(nil, _context, _max_age_key), do: true

  defp stale?(checked_at, context, max_age_key) do
    now = value(context, :now) || DateTime.utc_now(:microsecond)
    max_age_seconds = value(context, max_age_key) || @freshness_seconds
    DateTime.diff(now, checked_at, :second) > max_age_seconds
  end

  defp timestamp(nil), do: 0
  defp timestamp(%DateTime{} = datetime), do: DateTime.to_unix(datetime, :microsecond)

  defp finding(category, message, review_kind, extra \\ %{}) do
    %{
      "category" => category,
      "severity" => "blocking",
      "message" => message,
      "review_kind" => to_string(review_kind)
    }
    |> Map.merge(extra)
  end

  defp status([]), do: :passed
  defp status(_findings), do: :failed

  defp evidence_refs(reviews) do
    reviews
    |> Enum.map(&value(&1, :id))
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&"reviews/#{&1}")
  end

  defp normalize_kind(value) when is_atom(value), do: value

  defp normalize_kind(value) do
    value |> to_string() |> String.to_existing_atom()
  rescue
    ArgumentError -> :unknown
  end

  defp value(nil, _key), do: nil

  defp value(map, key) when is_map(map),
    do: Map.get(map, key) || Map.get(map, Atom.to_string(key))
end
