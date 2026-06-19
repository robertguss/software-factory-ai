defmodule Conveyor.Planning.PlanAmendments do
  @moduledoc """
  Deterministic PlanAmendmentProposal projection.

  The caller supplies already-resolved derivation/interface/authority indexes.
  This module does not mutate plans; it produces the proposal resource that a
  human or later policy step can accept, reject, or apply.
  """

  alias Conveyor.Evidence.InvalidationPreview
  alias Conveyor.Planning.ImpactPreview

  @schema_version "conveyor.plan_amendment_proposal@1"
  @nonmaterial_statuses ~w(clarification nonmaterial)
  @reusable_actions ~w(review_only presentation_erratum_only revalidate_only)

  @spec propose(map()) :: map()
  def propose(input) when is_map(input) do
    invalidation = InvalidationPreview.preview_invalidation(input)
    impact_preview = ImpactPreview.build(input)
    downstream_refs = downstream_refs(invalidation)

    %{
      "schema_version" => @schema_version,
      "plan_id" => value(input, :plan_id),
      "base_plan_revision_id" => value(input, :base_plan_revision_id),
      "dispute_kind" => value(input, :dispute_kind),
      "materiality" => value(input, :materiality),
      "affected_refs" => affected_refs(input, downstream_refs),
      "downstream_refs" => downstream_refs,
      "invalidated_artifact_refs" => invalidated_artifact_refs(invalidation),
      "impact_preview_ref" => impact_preview_ref(impact_preview),
      "status" => proposal_status(input)
    }
    |> put_optional("human_decision_id", value(input, :human_decision_id))
    |> put_optional("resulting_plan_revision_id", value(input, :resulting_plan_revision_id))
  end

  defp affected_refs(input, downstream_refs) do
    changed_refs(input)
    |> Kernel.++(epic_refs(input, downstream_refs))
    |> Kernel.++(grant_refs(input, downstream_refs))
    |> sort_refs()
  end

  defp changed_refs(input) do
    input
    |> list(:changed_subjects)
    |> Enum.map(fn subject ->
      ref(value(subject, :subject_kind), value(subject, :subject_id))
    end)
  end

  defp downstream_refs(invalidation) do
    invalidation
    |> Map.fetch!("affected_subjects")
    |> Enum.map(&subject_ref_to_resource_ref(&1["subject_ref"]))
    |> sort_refs()
  end

  defp invalidated_artifact_refs(invalidation) do
    invalidation
    |> Map.fetch!("affected_subjects")
    |> Enum.reject(&(&1["action"] in @reusable_actions))
    |> Enum.map(&subject_ref_to_resource_ref(&1["subject_ref"]))
    |> sort_refs()
  end

  defp epic_refs(input, downstream_refs) do
    downstream_subjects = subject_strings(downstream_refs)

    input
    |> graph_entries()
    |> Enum.filter(&(entry_subject(&1) in downstream_subjects))
    |> Enum.map(&value(&1, :epic_key))
    |> Enum.reject(&blank?/1)
    |> Enum.map(&ref("epic", &1))
  end

  defp grant_refs(input, downstream_refs) do
    downstream_subjects = subject_strings(downstream_refs)

    entry_grants =
      input
      |> graph_entries()
      |> Enum.filter(&(entry_subject(&1) in downstream_subjects))
      |> Enum.map(&value(&1, :grant_id))

    impact_grants =
      input
      |> list(:grant_impacts)
      |> Enum.map(&value(&1, :grant_id))

    (entry_grants ++ impact_grants)
    |> Enum.reject(&blank?/1)
    |> Enum.map(&ref("qualification_grant", &1))
  end

  defp graph_entries(input) do
    list(input, :artifact_inputs) ++
      list(input, :interface_bindings) ++
      list(input, :verification_obligations) ++
      list(input, :approval_roots)
  end

  defp entry_subject(entry) do
    cond do
      present?(value(entry, :consumer_artifact_id)) -> value(entry, :consumer_artifact_id)
      present?(value(entry, :id)) -> value(entry, :id)
      present?(value(entry, :root_id)) -> value(entry, :root_id)
      true -> nil
    end
  end

  defp impact_preview_ref(impact_preview) do
    %{
      "schema_version" => "conveyor.resource_ref@1",
      "kind" => "planning_impact_preview",
      "id_or_key" => "#{impact_preview["change_set_id"]}:impact-preview",
      "digest" => %{
        "schema_version" => "conveyor.digest_ref@1",
        "algorithm" => "sha256",
        "value" => String.replace_prefix(impact_preview["preview_digest"], "sha256:", "")
      }
    }
  end

  defp proposal_status(input) do
    if value(input, :materiality) in @nonmaterial_statuses do
      "accepted"
    else
      "human_review_required"
    end
  end

  defp subject_ref_to_resource_ref(subject_ref) do
    case String.split(to_string(subject_ref), ":", parts: 2) do
      [kind, id] -> ref(kind, id)
      [id] -> ref("artifact", id)
    end
  end

  defp subject_strings(refs) do
    MapSet.new(refs, &"#{&1["kind"]}:#{&1["id_or_key"]}")
  end

  defp ref(kind, id) do
    %{
      "schema_version" => "conveyor.resource_ref@1",
      "kind" => to_string(kind),
      "id_or_key" => to_string(id)
    }
  end

  defp sort_refs(refs) do
    refs
    |> Enum.reject(&(blank?(&1["kind"]) or blank?(&1["id_or_key"])))
    |> Enum.uniq()
    |> Enum.sort_by(&{&1["kind"], &1["id_or_key"]})
  end

  defp list(map, key) do
    case value(map, key, []) do
      values when is_list(values) -> values
      _other -> []
    end
  end

  defp value(map, key, default \\ nil) do
    Map.get(map, key, Map.get(map, to_string(key), default))
  end

  defp put_optional(map, _key, nil), do: map
  defp put_optional(map, _key, ""), do: map
  defp put_optional(map, key, value), do: Map.put(map, key, value)

  defp present?(value), do: not blank?(value)
  defp blank?(value), do: value in [nil, "", []]
end
