defmodule Conveyor.Planning.PreliminaryVerification do
  @moduledoc """
  Derives preliminary VerificationObligations from acceptance criteria and
  protected policies.

  Contract Forge may strengthen these later; this pass only creates the initial
  required, open obligations the graph can reason about.
  """

  alias Conveyor.Verification

  @spec derive(map()) :: map()
  def derive(input) when is_map(input) do
    normalized = normalize_value(input)

    entries =
      Map.get(normalized, :acceptance_criteria, []) ++
        Enum.map(
          Map.get(normalized, :protected_policies, []),
          &Map.put(&1, :obligation_kind, "policy")
        )

    {obligations, diagnostics} =
      Enum.map_reduce(entries, [], fn entry, diagnostics ->
        cond do
          not present?(Map.get(entry, :slice_key)) ->
            {nil, [missing_slice_diagnostic(entry) | diagnostics]}

          not valid_obligation_kind?(entry) ->
            # Report, don't crash (ADR-16): an unknown obligation_kind would raise inside
            # Verification.new_obligation!, aborting the whole preliminary-verification pass.
            {nil, [invalid_kind_diagnostic(entry) | diagnostics]}

          true ->
            {obligation(entry), diagnostics}
        end
      end)

    diagnostics = Enum.reverse(diagnostics)

    %{
      status: if(diagnostics == [], do: :ok, else: :blocked),
      obligations: Enum.reject(obligations, &is_nil/1),
      diagnostics: diagnostics
    }
  end

  defp obligation(entry) do
    key = Map.fetch!(entry, :key)

    Verification.new_obligation!(%{
      slice_id: Map.fetch!(entry, :slice_key),
      acceptance_ref: key,
      obligation_kind: Map.get(entry, :obligation_kind, "example"),
      required: true,
      oracle_definition_ref: "oracle:#{key}",
      evidence_requirement_ref: "evidence_requirement:#{key}",
      status: "open"
    })
  end

  defp missing_slice_diagnostic(entry) do
    %{
      rule_key: "verification_obligation_missing_slice",
      severity: :blocking,
      subject_key: Map.get(entry, :key, "unknown")
    }
  end

  defp valid_obligation_kind?(entry) do
    Map.get(entry, :obligation_kind, "example") in Verification.obligation_kinds()
  end

  defp invalid_kind_diagnostic(entry) do
    %{
      rule_key: "verification_obligation_invalid_kind",
      severity: :blocking,
      subject_key: Map.get(entry, :key, "unknown")
    }
  end

  defp present?(value), do: value not in [nil, "", []]

  defp normalize_value(%{} = map) do
    Map.new(map, fn {key, value} ->
      {key |> to_string() |> String.to_atom(), normalize_value(value)}
    end)
  end

  defp normalize_value(values) when is_list(values), do: Enum.map(values, &normalize_value/1)
  defp normalize_value(value), do: value
end
