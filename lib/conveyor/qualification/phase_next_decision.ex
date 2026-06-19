defmodule Conveyor.Qualification.PhaseNextDecision do
  @moduledoc """
  Updates PhaseNextDecision after P15-B8 qualification review.
  """

  @spec authorize_or_harden(map()) :: map()
  def authorize_or_harden(input) when is_map(input) do
    requested_scope = stringify_map(value(input, :requested_scope, %{}))
    grant = stringify_map(value(input, :grant, %{}))
    grant_scope = value(grant, :scope, %{})
    authorized? = scope_covers?(grant_scope, requested_scope)
    branch = if authorized?, do: "balanced", else: "gate_first"
    authorization_result = if authorized?, do: "authorized", else: "hardening_required"

    base = %{
      "schema_version" => "conveyor.phase_next_decision@1",
      "phase0_1_report_ref" => value(input, :phase0_1_report_ref),
      "baseline_freeze_ref" => value(input, :baseline_freeze_ref),
      "selected_branches" => [
        %{
          "branch" => branch,
          "response" => response(authorized?, requested_scope, grant_scope),
          "blocks_requested_grant" => not authorized?,
          "justification_refs" => value(input, :evidence_refs, [])
        }
      ],
      "evidence_refs" => value(input, :evidence_refs, []),
      "stop_the_line" => if(authorized?, do: [], else: [branch]),
      "requested_scope" => requested_scope,
      "qualification_grant_id" => value(grant, :id),
      "authorization_result" => authorization_result,
      "hardening_branch" => if(authorized?, do: nil, else: branch),
      "status" => "accepted",
      "created_at" => value(input, :created_at),
      "notes" => notes(authorized?)
    }

    Map.put(base, "decision_digest", digest(base))
  end

  defp response(true, requested_scope, _grant_scope) do
    "Requested P2 scope authorized by active QualificationGrant: #{scope_ref(requested_scope)}."
  end

  defp response(false, requested_scope, grant_scope) do
    "Requested P2 scope #{scope_ref(requested_scope)} exceeds grant scope #{scope_ref(grant_scope)}; open targeted hardening."
  end

  defp notes(true), do: "P15-B8 grant covers requested P2 scope."

  defp notes(false),
    do: "P15-B8 grant scope is insufficient; hardening branch required before P2 authorization."

  defp scope_covers?(supported_scope, requested_scope) do
    supported_scope = stringify_map(supported_scope)

    Enum.all?(requested_scope, fn {key, requested} ->
      Map.get(supported_scope, key) in [requested, "*"]
    end)
  end

  defp scope_ref(scope) do
    scope
    |> Enum.map(fn {key, value} -> "#{key}=#{value}" end)
    |> Enum.sort()
    |> Enum.join(",")
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

  defp value(map, key, default \\ nil) do
    Map.get(map, key, Map.get(map, to_string(key), default))
  end
end
