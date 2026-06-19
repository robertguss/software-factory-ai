defmodule Conveyor.Planning.PromptDryCompile do
  @moduledoc """
  Placeholder prompt-structure dry compiler.

  This validates that compiler output can satisfy prompt references without
  launching an implementer or calling a provider.
  """

  @required_fields [
    :acceptance_refs,
    :desired_behavior,
    :key_interfaces,
    :verification_obligation_refs
  ]

  @final_required_fields @required_fields ++ [:test_refs]
  @autonomy_rank %{"observe_only" => 0, "local_dev" => 1, "team" => 2, "release" => 3}

  @spec run(map()) :: map()
  def run(input) when is_map(input) do
    normalized = normalize_value(input)

    if Map.get(normalized, :mode) == :final do
      final_run(normalized)
    else
      placeholder_run(normalized)
    end
  end

  defp placeholder_run(normalized) do
    fields = Map.get(normalized, :contract_fields, %{})
    missing = Enum.filter(@required_fields, &(not present?(Map.get(fields, &1))))

    if missing == [] do
      %{
        status: :passed,
        implementer_launched?: false,
        provider_called?: false,
        prompt_structure: %{
          template_version: "placeholder-contract-prompt@1",
          slice_key: Map.fetch!(normalized, :slice_key),
          required_refs:
            Map.fetch!(fields, :acceptance_refs) ++
              Map.fetch!(fields, :key_interfaces) ++
              Map.fetch!(fields, :verification_obligation_refs)
        },
        critical_context_status:
          if(present?(Map.get(normalized, :critical_context_refs)), do: :complete, else: :missing)
      }
    else
      %{
        status: :blocked,
        implementer_launched?: false,
        provider_called?: false,
        missing_fields: missing
      }
    end
  end

  defp final_run(normalized) do
    fields = Map.get(normalized, :contract_fields, %{})
    missing = Enum.filter(@final_required_fields, &(not present?(Map.get(fields, &1))))
    required_refs = final_required_refs(normalized, fields)
    authorized = Map.get(normalized, :authorized_artifact_refs, [])
    unauthorized = Enum.reject(required_refs, &(&1 in authorized))
    conflicts = Map.get(normalized, :instruction_hierarchy_conflicts, [])
    autonomy_status = autonomy_status(normalized)

    blocked? =
      missing != [] or unauthorized != [] or conflicts != [] or autonomy_status != :within_grant

    context_manifest = Map.get(normalized, :context_manifest, %{})

    %{
      status: if(blocked?, do: :blocked, else: :passed),
      template_version: "final-slice-prompt@1",
      implementer_launched?: false,
      provider_called?: false,
      missing_fields: missing,
      instruction_hierarchy_conflicts: conflicts,
      unauthorized_artifact_refs: unauthorized,
      authorized_artifact_status: if(unauthorized == [], do: :complete, else: :missing),
      autonomy_status: autonomy_status,
      budget_result: %{
        token_budget: Map.get(context_manifest, :token_budget),
        shed_count: context_manifest |> Map.get(:shed_reasons, []) |> Enum.count()
      },
      prompt_structure: %{
        template_version: "final-slice-prompt@1",
        slice_key: Map.fetch!(normalized, :slice_key),
        required_refs: required_refs
      }
    }
  end

  defp final_required_refs(normalized, fields) do
    (Map.get(fields, :acceptance_refs, []) ++
       Map.get(fields, :key_interfaces, []) ++
       Map.get(fields, :verification_obligation_refs, []) ++
       Map.get(fields, :test_refs, []) ++
       [Map.get(normalized, :role_view_ref), Map.get(normalized, :output_schema_ref)] ++
       Map.get(normalized, :policy_refs, []))
    |> Enum.reject(&(&1 in [nil, ""]))
  end

  defp autonomy_status(normalized) do
    planned = Map.get(normalized, :planned_autonomy)
    capability = Map.get(normalized, :capability_autonomy)
    grant = Map.get(normalized, :grant_autonomy)

    if rank(planned) <= min(rank(capability), rank(grant)) do
      :within_grant
    else
      :exceeds_capability_or_grant
    end
  end

  defp rank(value), do: Map.get(@autonomy_rank, to_string(value), 999)

  defp present?(value), do: value not in [nil, "", []]

  defp normalize_value(%{} = map) do
    Map.new(map, fn {key, value} ->
      {key |> to_string() |> String.to_atom(), normalize_value(value)}
    end)
  end

  defp normalize_value(values) when is_list(values), do: Enum.map(values, &normalize_value/1)
  defp normalize_value(value), do: value
end
