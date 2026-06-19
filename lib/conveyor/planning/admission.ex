defmodule Conveyor.Planning.Admission do
  @moduledoc """
  Admission checks for Phase 2 planning modes.
  """

  @autonomy_order %{
    "informational" => 0,
    "local_dev" => 1,
    "team" => 2,
    "release" => 3
  }

  @spec admit(atom(), map(), map() | nil) :: {:ok, map()} | {:deny, [atom()]}
  def admit(:deterministic_parse_lint, _request, _grant) do
    {:ok,
     %{
       mode: :deterministic_parse_lint,
       authority: :read_only_parse_lint,
       approval_authority?: false
     }}
  end

  def admit(:agentic_planning, request, grant) when is_map(request) and is_map(grant) do
    reasons =
      []
      |> require_active(grant)
      |> require_all(:roles_not_covered, values(request, :roles), values(grant, :roles))
      |> require_all(:adapters_not_covered, values(request, :adapters), values(grant, :adapters))
      |> require_one(
        :environment_not_covered,
        value(request, :environment),
        values(grant, :environments)
      )
      |> require_all(
        :verification_not_covered,
        values(request, :verification),
        values(grant, :verification)
      )
      |> require_autonomy(value(request, :autonomy), value(grant, :max_autonomy))

    if reasons == [] do
      {:ok,
       %{
         mode: :agentic_planning,
         authority: :approval_eligible,
         approval_authority?: true
       }}
    else
      {:deny, Enum.reverse(reasons)}
    end
  end

  def admit(:agentic_planning, _request, _grant), do: {:deny, [:grant_required]}

  defp require_active(reasons, grant) do
    if value(grant, :status) == "active", do: reasons, else: [:grant_inactive | reasons]
  end

  defp require_all(reasons, reason, requested, covered) do
    if MapSet.subset?(MapSet.new(requested), MapSet.new(covered)) do
      reasons
    else
      [reason | reasons]
    end
  end

  defp require_one(reasons, reason, requested, covered) do
    if requested in covered, do: reasons, else: [reason | reasons]
  end

  defp require_autonomy(reasons, nil, _covered), do: reasons

  defp require_autonomy(reasons, requested, covered) do
    case Map.get(@autonomy_order, to_string(requested)) do
      nil ->
        # Explicitly-supplied but unsupported autonomy must fail closed (ADR-06), not be
        # treated as rank -1 (the lowest requirement, which any active grant would satisfy).
        [:autonomy_not_covered | reasons]

      requested_rank ->
        if autonomy_rank(covered) >= requested_rank,
          do: reasons,
          else: [:autonomy_not_covered | reasons]
    end
  end

  defp autonomy_rank(nil), do: -1
  defp autonomy_rank(level), do: Map.get(@autonomy_order, to_string(level), -1)

  defp values(map, key), do: List.wrap(value(map, key))
  defp value(map, key), do: Map.get(map, key) || Map.get(map, to_string(key))
end
