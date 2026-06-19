defmodule Conveyor.Verification.Cockpit do
  @moduledoc """
  Read-only Cockpit projection for verification obligations.

  The projection exposes coverage, invalid evidence, waivers, owners, expiry,
  and quarantine state without rewriting the underlying obligation authority.
  """

  @invalid_validities ~w(suspect invalid expired)

  @spec project(map(), keyword()) :: map()
  def project(inputs, opts \\ []) when is_map(inputs) and is_list(opts) do
    obligations = value(inputs, :obligations) || []
    evidence = value(inputs, :evidence) || []
    satisfactions = value(inputs, :satisfactions) || []
    waivers = value(inputs, :waivers) || []
    quarantines = value(inputs, :quarantines) || []

    rows =
      Enum.map(obligations, fn obligation ->
        obligation_row(obligation, evidence, satisfactions, waivers, quarantines)
      end)

    projection = %{
      "schema_version" => "conveyor.verification_cockpit_projection@1",
      "generated_at" => Keyword.fetch!(opts, :generated_at),
      "summary" => summary(rows),
      "obligations" => rows
    }

    Map.put(projection, "projection_digest", "sha256:#{digest(projection)}")
  end

  defp obligation_row(obligation, evidence, satisfactions, waivers, quarantines) do
    obligation_id = obligation["id"]
    satisfaction = latest_for_obligation(satisfactions, obligation_id)

    obligation_evidence =
      Enum.filter(evidence, &(&1["verification_obligation_id"] == obligation_id))

    invalid_evidence = Enum.filter(obligation_evidence, &(&1["validity"] in @invalid_validities))
    waiver = active_waiver(waivers, obligation_id)
    obligation_quarantines = active_quarantines(quarantines, obligation_id)

    %{
      "id" => obligation_id,
      "acceptance_ref" => obligation["acceptance_ref"],
      "obligation_kind" => obligation["obligation_kind"],
      "required" => obligation["required"],
      "satisfaction_result" => satisfaction_result(satisfaction),
      "valid_evidence_ids" => evidence_ids(obligation_evidence, ["valid"]),
      "invalid_evidence_ids" => Enum.map(invalid_evidence, & &1["id"]),
      "quarantine_ids" => Enum.map(obligation_quarantines, & &1["id"]),
      "waiver" => waiver_projection(waiver),
      "safe_next_action" =>
        safe_next_action(satisfaction, invalid_evidence, waiver, obligation_quarantines)
    }
  end

  defp latest_for_obligation(satisfactions, obligation_id) do
    satisfactions
    |> Enum.filter(&(&1["verification_obligation_id"] == obligation_id))
    |> Enum.sort_by(&(&1["evaluated_at"] || ""), :desc)
    |> List.first()
  end

  defp satisfaction_result(nil), do: "not_assessed"
  defp satisfaction_result(satisfaction), do: satisfaction["result"] || "not_assessed"

  defp evidence_ids(evidence, validities) do
    evidence
    |> Enum.filter(&(&1["validity"] in validities))
    |> Enum.map(& &1["id"])
  end

  defp active_waiver(waivers, obligation_id) do
    Enum.find(waivers, fn waiver ->
      waiver["verification_obligation_id"] == obligation_id and waiver["status"] == "active"
    end)
  end

  defp active_quarantines(quarantines, obligation_id) do
    Enum.filter(quarantines, fn quarantine ->
      quarantine["status"] == "quarantined" and
        obligation_id in (quarantine["required_for_obligation_ids"] || [])
    end)
  end

  defp waiver_projection(nil), do: nil

  defp waiver_projection(waiver) do
    %{
      "id" => waiver["id"],
      "owner" => waiver["owner"],
      "expires_at" => waiver["expires_at"],
      "max_autonomy" => waiver["max_autonomy"],
      "compensating_control_refs" => waiver["compensating_control_refs"]
    }
  end

  defp safe_next_action(_satisfaction, _invalid_evidence, _waiver, [_first | _rest]),
    do: "replace_quarantined_evidence_or_request_waiver"

  defp safe_next_action(_satisfaction, [_first | _rest], %{}, _quarantines),
    do: "replace_invalid_evidence_or_review_active_waiver"

  defp safe_next_action(%{"result" => "blocked"}, _invalid_evidence, _waiver, _quarantines),
    do: "collect_valid_evidence_or_request_waiver"

  defp safe_next_action(%{"result" => "waived"}, _invalid_evidence, _waiver, _quarantines),
    do: "monitor_waiver_expiry"

  defp safe_next_action(%{"result" => "satisfied"}, _invalid_evidence, _waiver, _quarantines),
    do: "none"

  defp safe_next_action(_satisfaction, _invalid_evidence, _waiver, _quarantines),
    do: "assess_required_evidence"

  defp summary(rows) do
    %{
      "required_obligations" => Enum.count(rows, & &1["required"]),
      "satisfied" => count_result(rows, "satisfied"),
      "blocked" => count_result(rows, "blocked"),
      "waived" => count_result(rows, "waived"),
      "not_assessed" => count_result(rows, "not_assessed"),
      "invalid_evidence" => rows |> Enum.flat_map(& &1["invalid_evidence_ids"]) |> length(),
      "active_waivers" => Enum.count(rows, & &1["waiver"])
    }
  end

  defp count_result(rows, result), do: Enum.count(rows, &(&1["satisfaction_result"] == result))

  defp digest(value) do
    value
    |> canonical()
    |> Jason.encode!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp canonical(map) when is_map(map) do
    map
    |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
    |> Map.new(fn {key, value} -> {key, canonical(value)} end)
  end

  defp canonical(values) when is_list(values), do: Enum.map(values, &canonical/1)
  defp canonical(value), do: value

  defp value(map, key) when is_map(map) do
    cond do
      Map.has_key?(map, key) -> Map.get(map, key)
      Map.has_key?(map, to_string(key)) -> Map.get(map, to_string(key))
      true -> nil
    end
  end
end
