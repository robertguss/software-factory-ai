defmodule Conveyor.ContractForge.ContractAuthor do
  @moduledoc """
  Materializes draft AgentBrief contracts from contract-author RoleViews.
  """

  alias Conveyor.ContractForge.ArchetypeTemplates
  alias Conveyor.ContractForge.FalsifierSeedDeriver
  alias Conveyor.ContractForge.VerificationObligationDeriver

  @spec materialize(map()) :: map()
  def materialize(input) when is_map(input) do
    normalized = stringify_map(input)
    role_view = Map.fetch!(normalized, "role_view")
    contract = contract(normalized, role_view)
    derivation_contract = derivation_contract(contract, normalized)

    case VerificationObligationDeriver.derive(derivation_contract) do
      {:ok, obligations} ->
        falsifier_seeds = FalsifierSeedDeriver.derive!(derivation_contract)

        %{
          status: :passed,
          authority_effect: :none,
          role_view: role_view,
          contract: contract,
          verification_obligations: obligations,
          falsifier_seeds: falsifier_seeds,
          findings: []
        }

      {:error, findings} ->
        %{
          status: :blocked,
          authority_effect: :none,
          role_view: role_view,
          contract: contract,
          verification_obligations: [],
          falsifier_seeds: [],
          findings: findings
        }
    end
  end

  defp contract(input, role_view) do
    archetype = Map.fetch!(input, "archetype")
    template = ArchetypeTemplates.fetch!(archetype)
    acceptance_criteria = Map.fetch!(input, "acceptance_criteria")
    obligations = obligation_refs(acceptance_criteria)
    bounded_context = Map.get(role_view, "bounded_context", [])

    base = %{
      "schema_version" => "conveyor.agent_brief_contract@1",
      "id" => "agent-brief-contract:#{Map.fetch!(input, "slice_id")}",
      "slice_id" => Map.fetch!(input, "slice_id"),
      "behavior" => Map.fetch!(input, "behavior"),
      "source_refs" => %{
        # Partition the bounded context by ref class so the requirements and decisions arrays
        # are not cross-contaminated (REQ-* vs DEC-*).
        "requirements" =>
          Enum.filter(bounded_context, &String.starts_with?(to_string(&1), "REQ-")),
        "decisions" => Enum.filter(bounded_context, &String.starts_with?(to_string(&1), "DEC-")),
        "constraints" => Map.get(role_view, "constraints", []),
        "claims" => Map.get(role_view, "claims", [])
      },
      "archetype" => archetype,
      "change_class" => Map.fetch!(input, "change_class"),
      "acceptance_criteria" => normalize_acceptance_criteria(acceptance_criteria),
      "verification_obligations" => obligations,
      "authorized_scope" => Map.fetch!(input, "authorized_scope"),
      "risk" => %{
        "level" => Map.get(input, "risk_level", "medium"),
        "required_review_lenses" => template["required_review_lenses"]
      },
      "assumptions" => Map.get(input, "assumptions", []),
      "challenge_cases" => Map.get(input, "challenge_cases", []),
      "rollout" => Map.fetch!(input, "rollout"),
      "recovery" => Map.fetch!(input, "recovery"),
      "out_of_scope" => Map.fetch!(input, "out_of_scope"),
      "claim_coverage" => [
        %{"field" => "behavior.desired", "claim_refs" => Map.get(role_view, "claims", [])}
      ]
    }

    Map.put(base, "contract_digest", digest(base))
  end

  defp derivation_contract(contract, input) do
    Map.put(contract, "acceptance_criteria", normalize_derivation_acceptance_criteria(input))
  end

  defp normalize_acceptance_criteria(criteria) do
    Enum.map(criteria, fn ac ->
      ac
      |> Map.take([
        "id",
        "text",
        "positive_examples",
        "negative_examples",
        "boundary_examples",
        "abuse_examples",
        "non_goal_examples",
        "falsifying_conditions"
      ])
      |> put_default_example_lists()
    end)
  end

  defp normalize_derivation_acceptance_criteria(input) do
    input
    |> Map.fetch!("acceptance_criteria")
    |> Enum.map(fn ac ->
      ac
      |> Map.take([
        "id",
        "text",
        "positive_examples",
        "negative_examples",
        "boundary_examples",
        "abuse_examples",
        "non_goal_examples",
        "falsifying_conditions",
        "machine_checkable",
        "verification_stage",
        "required_test_refs",
        "forbidden_predicates",
        "property_counterexamples",
        "metamorphic_relations",
        "interface_incompatibility_cases"
      ])
      |> put_default_example_lists()
    end)
  end

  defp put_default_example_lists(ac) do
    ac
    |> Map.put_new("positive_examples", [])
    |> Map.put_new("negative_examples", [])
    |> Map.put_new("boundary_examples", [])
    |> Map.put_new("abuse_examples", [])
    |> Map.put_new("non_goal_examples", [])
    |> Map.put_new("falsifying_conditions", [])
  end

  defp obligation_refs(criteria) do
    Enum.map(criteria, fn ac ->
      %{
        "id" => "VO-#{Map.fetch!(ac, "id")}",
        "acceptance_criterion_id" => Map.fetch!(ac, "id"),
        "obligation_kind" => Map.get(ac, "verification_stage", "unit"),
        "evidence_requirements" => Map.get(ac, "required_test_refs", [])
      }
    end)
  end

  defp digest(value) do
    encoded = value |> canonical_term() |> Jason.encode!()
    "sha256:" <> (:crypto.hash(:sha256, encoded) |> Base.encode16(case: :lower))
  end

  defp canonical_term(value) when is_map(value) do
    value
    |> stringify_map()
    |> Enum.sort_by(fn {key, _value} -> key end)
    |> Enum.map(fn {key, value} -> [key, canonical_term(value)] end)
  end

  defp canonical_term(values) when is_list(values), do: Enum.map(values, &canonical_term/1)
  defp canonical_term(value), do: value

  defp stringify_map(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), stringify_value(value)} end)
  end

  defp stringify_value(value) when is_map(value), do: stringify_map(value)
  defp stringify_value(values) when is_list(values), do: Enum.map(values, &stringify_value/1)
  defp stringify_value(value) when is_boolean(value), do: value
  defp stringify_value(value) when is_atom(value), do: Atom.to_string(value)
  defp stringify_value(value), do: value
end
