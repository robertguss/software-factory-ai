defmodule Conveyor.Evidence.Comparator do
  @moduledoc """
  Canonical multi-label evidence comparator.

  The comparator preserves all materiality labels and derives a deterministic
  dominant label for summaries. It is intentionally DB-free so CLI and
  diagnostic callers can compare already-resolved subjects.
  """

  @materiality_labels ~w(
    identical
    cosmetic
    context_only
    evidence_changing
    scope_added
    scope_removed
    scope_reinterpreted
    contract_changing
    acceptance_weakened
    acceptance_strengthened
    policy_weakened
    policy_strengthened
    environment_changing
    capability_changing
    approval_changing
    grant_changing
    incomparable
  )

  @precedence Map.new(Enum.with_index(@materiality_labels))

  @spec materiality_labels() :: [String.t()]
  def materiality_labels, do: @materiality_labels

  @spec compare(map(), map(), keyword()) :: map()
  def compare(left, right, opts \\ []) when is_map(left) and is_map(right) and is_list(opts) do
    {labels, incomparable_reason} =
      case invalid_subject_reason(left) || invalid_subject_reason(right) do
        nil ->
          labels =
            opts
            |> Keyword.get(:materiality_labels, inferred_labels(left, right))
            |> normalize_labels()

          {labels, nil}

        reason ->
          {["incomparable"], reason}
      end

    dominant_label = List.last(labels)

    %{
      left_subject_kind: subject_value(left, :subject_kind),
      left_subject_id: subject_value(left, :subject_id),
      right_subject_kind: subject_value(right, :subject_kind),
      right_subject_id: subject_value(right, :subject_id),
      materiality_labels: labels,
      dominant_label: dominant_label,
      summary_status: summary_status(dominant_label)
    }
    |> maybe_put_incomparable_reason(incomparable_reason)
  end

  defp invalid_subject_reason(subject) do
    cond do
      subject_value(subject, :available?) == false -> "subject_unavailable"
      subject_value(subject, :authorized?) == false -> "subject_unauthorized"
      subject_value(subject, :availability) in [:erased, "erased"] -> "subject_erased"
      subject_value(subject, :digest_verified?) == false -> "subject_digest_mismatch"
      true -> nil
    end
  end

  defp maybe_put_incomparable_reason(comparison, nil), do: comparison

  defp maybe_put_incomparable_reason(comparison, reason) do
    Map.put(comparison, :incomparable_reason, reason)
  end

  defp inferred_labels(left, right) do
    if subject_value(left, :digest) == subject_value(right, :digest) do
      [:identical]
    else
      [:evidence_changing]
    end
  end

  defp normalize_labels(labels) when is_list(labels) do
    labels
    |> Enum.map(&normalize_label!/1)
    |> Enum.uniq()
    |> Enum.sort_by(&Map.fetch!(@precedence, &1))
  end

  defp normalize_label!(label) do
    label = to_string(label)

    if label in @materiality_labels do
      label
    else
      raise ArgumentError, "unknown materiality label: #{label}"
    end
  end

  defp summary_status("identical"), do: "identical"
  defp summary_status("cosmetic"), do: "cosmetic"
  defp summary_status("incomparable"), do: "incomparable"
  defp summary_status(_dominant_label), do: "materially_different"

  defp subject_value(subject, key) do
    Map.get(subject, key, Map.get(subject, Atom.to_string(key)))
  end
end
