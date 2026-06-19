defmodule Conveyor.TestArchitect.FalsifierPreservation do
  @moduledoc """
  Derives falsifier preservation records from Test Architect artifacts.

  Compiler-derived falsifier seeds must be translated into a TestSpecification
  or explicitly superseded by stronger approved evidence. Anything else remains
  a dropped seed and blocks integrity.
  """

  alias Conveyor.Verification

  @spec evaluate!([map()], [map()], [map()], keyword()) :: %{
          preservations: [map()],
          report: map()
        }
  def evaluate!(seeds, test_specifications, supersessions, opts)
      when is_list(seeds) and is_list(test_specifications) and is_list(supersessions) and
             is_list(opts) do
    created_at = Keyword.fetch!(opts, :created_at)

    preservations =
      seeds
      |> Enum.flat_map(&preservation_for_seed(&1, test_specifications, supersessions, created_at))

    %{
      preservations: preservations,
      report: Verification.evaluate_falsifier_preservation(seeds, preservations)
    }
  end

  defp preservation_for_seed(seed, test_specifications, supersessions, created_at) do
    cond do
      translated = translated_spec(seed, test_specifications) ->
        [
          Verification.new_falsifier_preservation!(%{
            falsifier_seed_id: seed["id"],
            verification_obligation_id: seed["verification_obligation_id"],
            action: :translated,
            preserved_ref: translated["id"],
            created_at: created_at
          })
        ]

      supersession = supersession_for_seed(seed, supersessions) ->
        [
          Verification.new_falsifier_preservation!(%{
            falsifier_seed_id: seed["id"],
            verification_obligation_id: seed["verification_obligation_id"],
            action: :superseded,
            stronger_evidence_ref: value(supersession, :stronger_evidence_ref),
            human_decision_id: value(supersession, :human_decision_id),
            created_at: created_at
          })
        ]

      true ->
        []
    end
  end

  defp translated_spec(seed, test_specifications) do
    Enum.find(test_specifications, fn spec ->
      seed["id"] in Map.get(spec, "compiler_falsifier_seed_refs", []) and
        seed["verification_obligation_id"] in Map.get(spec, "verification_obligation_refs", []) and
        seed["acceptance_ref"] in Map.get(spec, "acceptance_refs", [])
    end)
  end

  defp supersession_for_seed(seed, supersessions) do
    Enum.find(supersessions, fn supersession ->
      value(supersession, :falsifier_seed_id) == seed["id"] and
        value(supersession, :verification_obligation_id) == seed["verification_obligation_id"]
    end)
  end

  defp value(map, key), do: Map.get(map, key, Map.get(map, to_string(key)))
end
