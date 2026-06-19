defmodule Conveyor.Evidence.InvalidationPreview do
  @moduledoc """
  Pure invalidation and impact-preview reducer.

  Callers pass the already-resolved derivation and authority indexes. The kernel
  does not read from the database; it projects affected subjects and why each
  subject must be regenerated, revalidated, or reapproved.
  """

  @schema_version "conveyor.invalidation_preview@1"
  @low_confidence_threshold 0.8

  @spec preview_invalidation(map()) :: map()
  def preview_invalidation(input) when is_map(input) do
    changed_subjects = changed_subjects(input)
    confidence = value(input, :impact_confidence)
    fail_wide? = low_confidence?(confidence)

    affected =
      if fail_wide?,
        do: wide_affected_subjects(input),
        else: affected_subjects(input, changed_subjects)

    %{
      "schema_version" => @schema_version,
      "change_set_id" => value(input, :change_set_id),
      "impact_confidence" => confidence,
      "confidence_status" => if(fail_wide?, do: "low_confidence_fail_wide", else: "selective"),
      "fail_wide" => fail_wide?,
      "affected_subjects" => affected
    }
  end

  defp affected_subjects(input, changed_subjects) do
    []
    |> Kernel.++(artifact_input_impacts(list(input, :artifact_inputs), changed_subjects))
    |> Kernel.++(interface_binding_impacts(list(input, :interface_bindings), changed_subjects))
    |> Kernel.++(decision_block_impacts(list(input, :decision_blocks), changed_subjects))
    |> Kernel.++(obligation_impacts(list(input, :verification_obligations), changed_subjects))
    |> Kernel.++(approval_root_impacts(list(input, :approval_roots), changed_subjects))
    |> Enum.uniq()
    |> Enum.sort_by(& &1["subject_ref"])
  end

  defp wide_affected_subjects(input) do
    []
    |> Kernel.++(
      Enum.map(list(input, :artifact_inputs), fn artifact_input ->
        %{
          "subject_ref" => value(artifact_input, :consumer_artifact_id),
          "action" => artifact_action(artifact_input),
          "reason" => "impact_confidence_low"
        }
      end)
    )
    |> Kernel.++(
      Enum.map(list(input, :interface_bindings), fn binding ->
        %{
          "subject_ref" => value(binding, :consumer_artifact_id),
          "action" => "recompile_prompt",
          "reason" => "impact_confidence_low"
        }
      end)
    )
    |> Kernel.++(
      Enum.map(list(input, :decision_blocks), fn decision_block ->
        %{
          "subject_ref" => value(decision_block, :decision_block_id),
          "action" => "regenerate_claims",
          "reason" => "impact_confidence_low"
        }
      end)
    )
    |> Kernel.++(
      Enum.map(list(input, :verification_obligations), fn obligation ->
        %{
          "subject_ref" => value(obligation, :id),
          "action" => "regenerate_verification_obligations",
          "reason" => "impact_confidence_low"
        }
      end)
    )
    |> Kernel.++(
      Enum.map(list(input, :approval_roots), fn approval_root ->
        %{
          "subject_ref" => value(approval_root, :root_id),
          "action" => approval_action(value(approval_root, :root_kind)),
          "reason" => "impact_confidence_low"
        }
      end)
    )
    |> Enum.reject(&is_nil(&1["subject_ref"]))
    |> Enum.uniq()
    |> Enum.sort_by(& &1["subject_ref"])
  end

  defp artifact_input_impacts(artifact_inputs, changed_subjects) do
    artifact_inputs
    |> Enum.filter(
      &(subject_key(value(&1, :input_subject_kind), value(&1, :input_subject_id)) in changed_subjects)
    )
    |> Enum.reject(&(value(&1, :invalidation_policy) == "ignore_after_capture"))
    |> Enum.map(fn artifact_input ->
      %{
        "subject_ref" => value(artifact_input, :consumer_artifact_id),
        "action" => artifact_action(artifact_input),
        "reason" => "artifact_input_changed"
      }
    end)
  end

  defp interface_binding_impacts(interface_bindings, changed_subjects) do
    interface_bindings
    |> Enum.filter(
      &(subject_key("interface_contract", value(&1, :interface_id)) in changed_subjects)
    )
    |> Enum.map(fn binding ->
      %{
        "subject_ref" => value(binding, :consumer_artifact_id),
        "action" => "recompile_prompt",
        "reason" => "interface_binding_changed"
      }
    end)
  end

  defp decision_block_impacts(decision_blocks, changed_subjects) do
    decision_blocks
    |> Enum.filter(
      &(subject_key(value(&1, :subject_kind), value(&1, :subject_id)) in changed_subjects)
    )
    |> Enum.map(fn decision_block ->
      %{
        "subject_ref" => value(decision_block, :decision_block_id),
        "action" => "regenerate_claims",
        "reason" => "decision_block_changed"
      }
    end)
  end

  defp obligation_impacts(obligations, changed_subjects) do
    obligations
    |> Enum.filter(
      &(subject_key(value(&1, :subject_kind), value(&1, :subject_id)) in changed_subjects)
    )
    |> Enum.map(fn obligation ->
      %{
        "subject_ref" => value(obligation, :id),
        "action" => "regenerate_verification_obligations",
        "reason" => "verification_obligation_changed"
      }
    end)
  end

  defp approval_root_impacts(approval_roots, changed_subjects) do
    approval_roots
    |> Enum.filter(
      &(subject_key(value(&1, :subject_kind), value(&1, :subject_id)) in changed_subjects)
    )
    |> Enum.map(fn approval_root ->
      %{
        "subject_ref" => value(approval_root, :root_id),
        "action" => approval_action(value(approval_root, :root_kind)),
        "reason" => "approval_root_changed"
      }
    end)
  end

  defp changed_subjects(input) do
    input
    |> list(:changed_subjects)
    |> Enum.map(&subject_key(value(&1, :subject_kind), value(&1, :subject_id)))
    |> MapSet.new()
  end

  defp artifact_action(artifact_input) do
    case value(artifact_input, :role) do
      "semantic" -> "regenerate_contract"
      "authority" -> "reapprove_shared_root"
      "evidence" -> "revalidate_only"
      "advisory" -> "review_only"
      "presentation" -> "presentation_erratum_only"
      _other -> "revalidate_only"
    end
  end

  defp approval_action("epic_authority"), do: "reapprove_epic"
  defp approval_action("shared_authority"), do: "reapprove_shared_root"
  defp approval_action(_root_kind), do: "reapprove_shared_root"

  defp low_confidence?(confidence) when is_number(confidence),
    do: confidence < @low_confidence_threshold

  defp low_confidence?(_confidence), do: true

  defp subject_key(kind, id), do: "#{kind}:#{id}"

  defp list(map, key) do
    case value(map, key, []) do
      values when is_list(values) -> values
      _other -> []
    end
  end

  defp value(map, key, default \\ nil) do
    string_key = to_string(key)

    Map.get(map, key, Map.get(map, string_key, default))
  end
end
