defmodule Conveyor.Planning.PilotRetrospective do
  @moduledoc """
  Builds the pilot retrospective and class-separated Chronicle projection.
  """

  @failure_classes ~w(plan compiler context implementation evidence adapter operator)

  @spec build(map()) :: map()
  def build(input) when is_map(input) do
    failures = list(input, :failures)
    release_failure_reasons = release_failure_reasons(input)
    failure_class_counts = failure_class_counts(failures)
    all_typed? = Enum.all?(failures, &typed_failure?/1)

    %{
      "status" =>
        if(release_failure_reasons == [], do: "retrospective_recorded", else: "release_failure"),
      "release_failure_reasons" => release_failure_reasons,
      "failure_class_counts" => failure_class_counts,
      "all_failures_have_typed_recovery" => all_typed?,
      "chronicle_markdown" => chronicle_markdown(failures, failure_class_counts)
    }
  end

  defp release_failure_reasons(input) do
    []
    |> maybe(selected_set_changed?(input), "selected_set_changed_after_outcomes")
    |> maybe(list(input, :replacement_attempts) != [], "failed_selection_replaced")
    |> maybe(from_scratch_manual_rewrite?(input), "from_scratch_manual_contract_rewrite")
    |> Enum.reverse()
  end

  defp selected_set_changed?(input) do
    MapSet.new(strings(input, :selected_slice_ids)) !=
      MapSet.new(strings(input, :final_selected_slice_ids))
  end

  defp from_scratch_manual_rewrite?(input) do
    input
    |> list(:manual_interventions)
    |> Enum.any?(fn intervention ->
      # ADR-22: a from-scratch manual contract reconstruction is a release failure on its
      # own, regardless of how the actor labels it. Gating on counts_as_generated_success
      # let the honest (label=false) case escape the gate entirely.
      value(intervention, :intervention_kind) == "contract_edit" and
        value(intervention, :reconstruction_kind) == "from_scratch"
    end)
  end

  defp failure_class_counts(failures) do
    failures
    |> Enum.frequencies_by(&value(&1, :failure_class))
    |> Map.new(fn {failure_class, count} -> {to_string(failure_class), count} end)
  end

  defp typed_failure?(failure) do
    present?(value(failure, :comparison_ref)) and
      present?(value(failure, :diagnosis_ref)) and
      present?(value(failure, :recovery_ref))
  end

  defp chronicle_markdown(failures, failure_class_counts) do
    sections =
      @failure_classes
      |> Enum.map(fn failure_class ->
        class_failures = Enum.filter(failures, &(value(&1, :failure_class) == failure_class))
        heading = "## #{failure_class |> String.capitalize()} Failures"

        body =
          if class_failures == [],
            do: "- none",
            else: Enum.map_join(class_failures, "\n", &failure_line/1)

        "#{heading}\n\n#{body}"
      end)

    [
      "# P2-B7 Pilot Retrospective",
      "",
      "Failure class counts: #{Jason.encode!(failure_class_counts)}",
      "",
      Enum.join(sections, "\n\n")
    ]
    |> Enum.join("\n")
  end

  defp failure_line(failure) do
    "- #{value(failure, :slice_id)} comparison=#{value(failure, :comparison_ref)} diagnosis=#{value(failure, :diagnosis_ref)} recovery=#{value(failure, :recovery_ref)}"
  end

  defp maybe(reasons, true, reason), do: [reason | reasons]
  defp maybe(reasons, false, _reason), do: reasons

  defp strings(map, key) do
    map
    |> value(key, [])
    |> List.wrap()
    |> Enum.map(&to_string/1)
  end

  defp list(map, key) do
    case value(map, key, []) do
      values when is_list(values) -> values
      _other -> []
    end
  end

  defp value(map, key, default \\ nil),
    do: Map.get(map, key, Map.get(map, to_string(key), default))

  defp present?(value), do: value not in [nil, "", []]
end
