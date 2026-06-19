defmodule Conveyor.Planning.WorkbenchActions do
  @moduledoc """
  Compiles structured Workbench actions into append-only ChangeSets.
  """

  @schema_version "conveyor.change_set@1"
  @actions ~w(
    approve_epic
    reject_epic
    select_candidate
    accept_claim
    reject_claim
    accept_assumption
    reject_assumption
    accept_waiver
    reject_waiver
    split
    merge
    reclassify_edge
    change_constraint
    change_interface
    change_compatibility
    mark_human_verification
    strengthen_contract
    show_cheapest_wrong_impl
    rerun_affected
    preview_invalidation
    open_amendment
    save_draft
    stop
    resume
  )

  @spec catalog() :: [String.t()]
  def catalog, do: @actions

  @spec compile(map()) :: map()
  def compile(input) when is_map(input) do
    normalized = stringify_map(input)
    blocking_reasons = blocking_reasons(normalized)

    if blocking_reasons == [] do
      change_set = change_set(normalized)

      %{
        "status" => "draft",
        "authority_effect" => "none",
        "mutation_mode" => "append_only_change_set",
        "blocking_reasons" => [],
        "change_set" => change_set
      }
    else
      %{
        "status" => "blocked",
        "authority_effect" => "none",
        "mutation_mode" => "append_only_change_set",
        "blocking_reasons" => blocking_reasons,
        "change_set" => nil
      }
    end
  end

  defp blocking_reasons(input) do
    []
    |> require_present(input, "action_type")
    |> require_known_action(input)
    |> require_present(input, "subject")
    |> require_present(input, "base_revision_digest")
    |> require_present(input, "impact_preview_ref")
    |> Enum.reverse()
  end

  defp require_known_action(reasons, input) do
    if input["action_type"] in @actions do
      reasons
    else
      ["unknown_action_type" | reasons]
    end
  end

  defp require_present(reasons, input, key) do
    if present?(input[key]), do: reasons, else: ["#{key}_missing" | reasons]
  end

  defp change_set(input) do
    base =
      %{
        "schema_version" => @schema_version,
        "subject" => input["subject"],
        "base_revision_digest" => input["base_revision_digest"],
        "operations" => [operation(input)],
        "preconditions" => preconditions(input),
        "materiality_labels" => input["materiality_labels"] || ["review_only"],
        "impact_preview_ref" => input["impact_preview_ref"],
        "status" => "draft"
      }
      |> put_optional("base_authority_root_digest", input["base_authority_root_digest"])

    Map.put(base, "change_set_digest", digest_ref(base))
  end

  defp operation(%{"action_type" => "select_candidate"} = input) do
    %{
      "op" => "replace",
      "path" => "/candidate_selection_id",
      "value" => input["value"],
      "reason" => input["reason"] || "select_candidate"
    }
  end

  defp operation(input) do
    %{
      "op" => "add",
      "path" => "/actions/#{input["action_type"]}",
      "value" => input["value"] || input["action_type"],
      "reason" => input["reason"] || input["action_type"]
    }
  end

  defp preconditions(input) do
    [
      %{"kind" => "base_revision_digest", "digest" => input["base_revision_digest"]}
    ]
    |> maybe_precondition("base_authority_root_digest", input["base_authority_root_digest"])
  end

  defp maybe_precondition(preconditions, _kind, nil), do: preconditions

  defp maybe_precondition(preconditions, kind, digest),
    do: preconditions ++ [%{"kind" => kind, "digest" => digest}]

  defp digest_ref(value) do
    %{
      "schema_version" => "conveyor.digest_ref@1",
      "algorithm" => "sha256",
      "value" =>
        value
        |> canonical_json()
        |> then(&:crypto.hash(:sha256, &1))
        |> Base.encode16(case: :lower)
    }
  end

  defp canonical_json(%{} = map) do
    entries =
      map
      |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
      |> Enum.map(fn {key, nested} ->
        Jason.encode!(to_string(key)) <> ":" <> canonical_json(nested)
      end)

    "{" <> Enum.join(entries, ",") <> "}"
  end

  defp canonical_json(values) when is_list(values),
    do: "[" <> Enum.map_join(values, ",", &canonical_json/1) <> "]"

  defp canonical_json(value) when is_atom(value), do: value |> Atom.to_string() |> Jason.encode!()
  defp canonical_json(value), do: Jason.encode!(value)

  defp put_optional(map, _key, nil), do: map
  defp put_optional(map, key, value), do: Map.put(map, key, value)

  defp present?(value), do: value not in [nil, "", []]

  defp stringify_map(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), stringify_value(value)} end)
  end

  defp stringify_value(value) when is_map(value), do: stringify_map(value)
  defp stringify_value(values) when is_list(values), do: Enum.map(values, &stringify_value/1)
  defp stringify_value(value) when is_atom(value), do: Atom.to_string(value)
  defp stringify_value(value), do: value
end
