defmodule Conveyor.Genome.BackEdge do
  @moduledoc """
  Mints gate-verified code provenance edges after a passing gate.
  """

  alias Conveyor.Factory
  alias Conveyor.Factory.AgentBrief
  alias Conveyor.Factory.CodeProvenanceEdge
  alias Conveyor.Factory.GateResult
  alias Conveyor.Factory.PatchSet
  alias Conveyor.Factory.RunAttempt
  alias Conveyor.Factory.RunSpec
  alias Conveyor.Factory.Slice

  @schema_version "conveyor.code_provenance_edge@1"
  @role "verified_by_gate"
  @invalidation_policy "invalidate_on_change"

  @spec mint!(map(), GateResult.t(), keyword()) :: [CodeProvenanceEdge.t()]
  def mint!(context, gate_result, opts \\ [])

  def mint!(context, %GateResult{passed: true} = gate_result, _opts) when is_map(context) do
    run_attempt = run_attempt!(context)
    slice = slice!(context, run_attempt)
    run_spec = run_spec!(context, run_attempt)
    criteria = acceptance_criteria(context, slice)

    if criteria == [] do
      []
    else
      patch_sha256 = patch_sha256(context, run_attempt, run_spec)
      claims = claims_by_pointer(context, criteria)
      claim_set_digest = Conveyor.CanonicalJson.digest(claims)
      symbols = code_symbols(context, run_attempt, patch_sha256)

      for {criterion, index} <- Enum.with_index(criteria),
          code_symbol <- symbols do
        claim_pointer = "/acceptance_criteria/#{index}"
        claim = Map.get(claims, claim_pointer, %{})

        create_edge!(%{
          run_attempt_id: run_attempt.id,
          slice_id: slice.id,
          gate_result_id: gate_result.id,
          code_symbol: code_symbol,
          claim_pointer: claim_pointer,
          claim_origin: claim_origin(claim),
          acceptance_criterion_id: criterion_id(criterion, index),
          decision: :passed,
          patch_sha256: patch_sha256,
          contract_lock_sha256: contract_lock_sha256(context, run_spec),
          claim_set_digest: claim_set_digest
        })
      end
    end
  end

  def mint!(_context, %GateResult{} = _gate_result, _opts), do: []

  defp create_edge!(attrs) do
    attrs =
      attrs
      |> Map.put(:schema_version, @schema_version)
      |> Map.put(:role, @role)
      |> Map.put(:invalidation_policy, @invalidation_policy)

    Ash.create!(
      CodeProvenanceEdge,
      Map.put(attrs, :edge_sha256, Conveyor.CanonicalJson.digest(attrs)),
      domain: Factory
    )
  end

  defp acceptance_criteria(context, slice) do
    case list(value(context, :acceptance_criteria)) do
      [] -> latest_brief_criteria(slice.id)
      criteria -> criteria
    end
  end

  defp latest_brief_criteria(slice_id) do
    AgentBrief
    |> Ash.read!(domain: Factory)
    |> Enum.filter(&(&1.slice_id == slice_id))
    |> Enum.sort_by(& &1.version, :desc)
    |> List.first()
    |> case do
      %AgentBrief{} = brief -> brief.acceptance_criteria
      nil -> []
    end
  end

  defp claims_by_pointer(context, criteria) do
    case value(context, :claims_by_pointer) do
      nil -> default_claims(criteria)
      claims -> stringify_claim_keys(claims)
    end
  end

  defp default_claims(criteria) do
    criteria
    |> Enum.with_index()
    |> Map.new(fn {criterion, index} ->
      {"/acceptance_criteria/#{index}",
       %{
         "origin" => "gate_verified",
         "source_anchor_refs" => list(value(criterion, :requirement_refs))
       }}
    end)
  end

  defp stringify_claim_keys(claims) do
    Map.new(claims, fn {pointer, claim} -> {to_string(pointer), stringify_map(claim)} end)
  end

  defp stringify_map(map) when is_map(map) do
    Map.new(map, fn {key, nested} -> {to_string(key), stringify_value(nested)} end)
  end

  defp stringify_value(value) when is_map(value), do: stringify_map(value)
  defp stringify_value(values) when is_list(values), do: Enum.map(values, &stringify_value/1)
  defp stringify_value(value) when is_atom(value), do: Atom.to_string(value)
  defp stringify_value(value), do: value

  defp code_symbols(context, run_attempt, patch_sha256) do
    list(value(context, :code_symbols))
    |> fallback(fn -> changed_files(run_attempt) end)
    |> fallback(fn -> provenance_subject_names(context) end)
    |> fallback(fn -> ["patch:#{strip_sha256(patch_sha256)}"] end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp changed_files(run_attempt) do
    case latest_patch_set(run_attempt) do
      %PatchSet{} = patch_set -> patch_set.changed_files
      nil -> []
    end
  end

  defp provenance_subject_names(context) do
    context
    |> value(:provenance_subjects, [])
    |> list()
    |> Enum.map(&(value(&1, :name) || value(&1, :subject_id)))
    |> Enum.reject(&blank?/1)
  end

  defp patch_sha256(context, run_attempt, run_spec) do
    value(context, :patch_sha256) ||
      context |> value(:patch_set) |> value(:patch_sha256) ||
      run_attempt |> latest_patch_set() |> value(:patch_sha256) ||
      run_spec.run_spec_sha256
  end

  defp latest_patch_set(run_attempt) do
    PatchSet
    |> Ash.read!(domain: Factory)
    |> Enum.filter(&(&1.run_attempt_id == run_attempt.id))
    |> Enum.sort_by(&DateTime.to_unix(&1.generated_at, :microsecond), :desc)
    |> List.first()
  end

  defp contract_lock_sha256(context, run_spec) do
    value(context, :contract_lock_sha256) || run_spec.contract_lock_sha256
  end

  defp claim_origin(claim), do: to_string(value(claim, :origin, "unknown"))

  defp criterion_id(criterion, index),
    do: value(criterion, :id) || "acceptance_criterion:#{index}"

  defp run_attempt!(context) do
    value(context, :run_attempt) || get_by_id!(RunAttempt, value(context, :run_attempt_id))
  end

  defp slice!(context, run_attempt) do
    value(context, :slice) || get_by_id!(Slice, run_attempt.slice_id)
  end

  defp run_spec!(context, run_attempt) do
    value(context, :run_spec) || get_by_id!(RunSpec, run_attempt.run_spec_id)
  end

  defp get_by_id!(resource, id) do
    resource
    |> Ash.read!(domain: Factory)
    |> Enum.find(&(&1.id == id)) ||
      raise ArgumentError, "#{inspect(resource)} #{id} was not found"
  end

  defp list(nil), do: []
  defp list(values) when is_list(values), do: values
  defp list(value), do: [value]

  defp value(map, key, default \\ nil)

  defp value(nil, _key, default), do: default

  defp value(map, key, default) when is_map(map),
    do: Map.get(map, key, Map.get(map, to_string(key), default))

  defp value(_value, _key, default), do: default

  defp fallback([], fun), do: fun.()
  defp fallback(values, _fun), do: values

  defp strip_sha256("sha256:" <> digest), do: digest
  defp strip_sha256(digest), do: digest

  defp blank?(value), do: is_nil(value) or (is_binary(value) and String.trim(value) == "")
end
