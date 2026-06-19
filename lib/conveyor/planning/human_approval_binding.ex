defmodule Conveyor.Planning.HumanApprovalBinding do
  @moduledoc """
  Binds human approvals to exact authority and review roots.
  """

  @spec bind(map()) :: map()
  def bind(input) when is_map(input) do
    normalized = stringify_map(input)
    blocking_reasons = blocking_reasons(normalized)

    if blocking_reasons == [] do
      human_approval = human_approval(normalized)
      approval_set = approval_set(normalized, human_approval)

      %{
        "status" => "approved",
        "blocking_reasons" => [],
        "human_approval" => human_approval,
        "approval_set" => approval_set
      }
    else
      %{
        "status" => "blocked",
        "blocking_reasons" => blocking_reasons,
        "human_approval" => nil,
        "approval_set" => nil
      }
    end
  end

  defp blocking_reasons(input) do
    []
    |> require_present(input, "approval_id")
    |> require_present(input, "shared_authority_root")
    |> require_present(input, "review_root")
    |> require_selected_epic_roots(input)
    |> Enum.reverse()
  end

  defp require_selected_epic_roots(reasons, input) do
    roots = input["epic_authority_roots"] || %{}

    missing =
      input
      |> list("selected_epics")
      |> Enum.reject(&Map.has_key?(roots, &1))

    if missing == [], do: reasons, else: ["selected_epic_root_missing" | reasons]
  end

  defp require_present(reasons, input, key) do
    if present?(input[key]), do: reasons, else: ["#{key}_missing" | reasons]
  end

  defp human_approval(input) do
    %{
      "schema_version" => "conveyor.human_approval_binding@1",
      "approval_id" => input["approval_id"],
      "actor" => input["actor"],
      "shared_authority_root_digest" => input["shared_authority_root"],
      "selected_epic_authority_roots" => selected_epic_roots(input),
      "review_root_digest" => input["review_root"],
      "approval_policy_key" => value(input["approval_policy"], "policy_key"),
      "accepted_warnings" => sorted_strings(input, "accepted_warnings"),
      "accepted_assumptions" => sorted_strings(input, "accepted_assumptions"),
      "accepted_waivers" => sorted_strings(input, "accepted_waivers"),
      "autonomy_ceiling" => input["autonomy_ceiling"],
      "signature_status" => input["signature_status"] || "unsigned"
    }
  end

  defp approval_set(input, human_approval) do
    approval_policy = input["approval_policy"] || %{}
    threshold = value(approval_policy, "threshold", 1)
    approval_ids = [human_approval["approval_id"]]

    base = %{
      "schema_version" => "conveyor.approval_set@1",
      "subject_authority_roots" =>
        [
          %{"root_kind" => "shared_authority", "digest" => input["shared_authority_root"]}
        ] ++
          Enum.map(human_approval["selected_epic_authority_roots"], fn root ->
            %{
              "root_kind" => "epic_authority",
              "epic_key" => root["epic_key"],
              "digest" => root["digest"]
            }
          end),
      "review_root_digest" => input["review_root"],
      "approval_policy_digest" => value(approval_policy, "policy_digest", zero_digest()),
      "approval_ids" => approval_ids,
      "threshold_satisfied" => length(approval_ids) >= threshold,
      "active_revocation_events" => []
    }

    Map.put(base, "approval_set_digest", digest_ref(base))
  end

  defp selected_epic_roots(input) do
    roots = input["epic_authority_roots"] || %{}

    input
    |> list("selected_epics")
    |> Enum.sort()
    |> Enum.map(fn epic_key ->
      %{"epic_key" => epic_key, "digest" => Map.fetch!(roots, epic_key)}
    end)
  end

  defp sorted_strings(input, key) do
    input
    |> list(key)
    |> Enum.map(&to_string/1)
    |> Enum.sort()
  end

  defp list(map, key) do
    case value(map, key, []) do
      values when is_list(values) -> values
      _other -> []
    end
  end

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

  defp zero_digest do
    %{
      "schema_version" => "conveyor.digest_ref@1",
      "algorithm" => "sha256",
      "value" => String.duplicate("0", 64)
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

  defp present?(value), do: value not in [nil, "", []]

  defp stringify_map(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), stringify_value(value)} end)
  end

  defp stringify_value(value) when is_map(value), do: stringify_map(value)
  defp stringify_value(values) when is_list(values), do: Enum.map(values, &stringify_value/1)
  defp stringify_value(value) when is_atom(value), do: Atom.to_string(value)
  defp stringify_value(value), do: value

  defp value(map, key, default \\ nil)
  defp value(nil, _key, default), do: default
  defp value(map, key, default), do: Map.get(map, key, Map.get(map, to_string(key), default))
end
