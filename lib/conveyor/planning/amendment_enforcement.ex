defmodule Conveyor.Planning.AmendmentEnforcement do
  @moduledoc """
  Enforces contract-evolution authority rules for material amendments.
  """

  @manual_schema_version "conveyor.manual_intervention_artifact@1"
  @reapproval_labels ~w(material breaking acceptance_criteria obligation decision hard_constraint scope compatibility waiver risk public_interface)

  @spec plan(map()) :: map()
  def plan(input) when is_map(input) do
    if material_change?(input) do
      revision_id = value(input, :resulting_plan_revision_id)

      %{
        "status" => "new_attempt_required",
        "terminated_attempt_id" => value(input, :base_attempt_id),
        "retry_budget_effect" => retry_budget_effect(input),
        "retry_budget_remaining" => value(input, :retry_budget_remaining),
        "prior_attempt_reused" => false,
        "created_refs" => created_refs(revision_id)
      }
    else
      %{
        "status" => "no_new_attempt_required",
        "terminated_attempt_id" => nil,
        "retry_budget_effect" => "unchanged",
        "retry_budget_remaining" => value(input, :retry_budget_remaining),
        "prior_attempt_reused" => true,
        "created_refs" => []
      }
    end
  end

  @spec manual_intervention_artifact(map()) :: map()
  def manual_intervention_artifact(input) when is_map(input) do
    labels = strings(input, :materiality_labels)

    %{
      "schema_version" => @manual_schema_version,
      "intervention_kind" => value(input, :intervention_kind),
      "subject_ref" => value(input, :subject_ref),
      "content_ref" => value(input, :content_ref),
      "actor_action_id" => value(input, :actor_action_id),
      "reason" => value(input, :reason),
      "affected_refs" => list(input, :affected_refs),
      "materiality_labels" => labels,
      "counts_as_generated_success" => value(input, :counts_as_generated_success, false),
      "requires_reapproval" => value(input, :requires_reapproval, requires_reapproval?(labels)),
      "created_at" => value(input, :created_at)
    }
    |> put_optional("base_authority_root_digest", value(input, :base_authority_root_digest))
  end

  @spec manual_intervention_verdict(map()) :: map()
  def manual_intervention_verdict(input) when is_map(input) do
    artifact = value(input, :manual_intervention_artifact)

    cond do
      value(input, :manual_reconstruction_detected) == true and is_nil(artifact) ->
        %{"status" => "release_failure", "reason" => "hidden_manual_reconstruction"}

      is_map(artifact) and artifact["counts_as_generated_success"] == true ->
        %{
          "status" => "release_failure",
          "reason" => "manual_intervention_counted_as_generated_success"
        }

      true ->
        %{"status" => "recorded", "reason" => "typed_manual_intervention"}
    end
  end

  defp material_change?(input), do: value(input, :materiality) in ["material", "breaking"]

  defp retry_budget_effect(input) do
    if value(input, :fault_class) == "contract_fault" do
      "not_consumed_contract_fault"
    else
      "not_consumed_contract_change"
    end
  end

  defp created_refs(revision_id) do
    [
      resource_ref("authority_root", "authority-root:#{revision_id}"),
      resource_ref("contract_lock", "contract-lock:#{revision_id}"),
      resource_ref("run_spec", "run-spec:#{revision_id}"),
      resource_ref("run_attempt", "run-attempt:#{revision_id}")
    ]
  end

  defp resource_ref(kind, id) do
    %{"schema_version" => "conveyor.resource_ref@1", "kind" => kind, "id_or_key" => id}
  end

  defp requires_reapproval?(labels), do: Enum.any?(labels, &(&1 in @reapproval_labels))

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

  defp put_optional(map, _key, nil), do: map
  defp put_optional(map, key, value), do: Map.put(map, key, value)
end
