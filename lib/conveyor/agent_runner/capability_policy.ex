defmodule Conveyor.AgentRunner.CapabilityPolicy do
  @moduledoc """
  Derives effective adapter capabilities from claims and policy inputs.

  The adapter name is recorded as evidence context only. Capability decisions
  come from declared/probed/observed claim agreement, health, policy, and a
  valid admission permit.
  """

  alias Conveyor.AgentRunner.Capabilities

  @sources ~w(declared probed observed)
  @default_derived_at "1970-01-01T00:00:00Z"

  @spec derive!(String.t(), [map()], keyword()) :: map()
  def derive!(adapter, claims, opts \\ []) when is_binary(adapter) and is_list(claims) do
    policy = Keyword.get(opts, :policy, %{})
    health = Keyword.get(opts, :health, %{state: :closed})
    derived_at = Keyword.get(opts, :derived_at, @default_derived_at)

    candidates =
      claims
      |> Enum.group_by(&value(&1, "capability_key"))
      |> Enum.sort_by(fn {key, _claims} -> key end)
      |> Enum.map(fn {key, grouped_claims} -> candidate(key, grouped_claims, policy) end)

    health_open? = value(health, :state) == :open

    effective_capabilities =
      if health_open? do
        %{}
      else
        candidates
        |> Enum.filter(&(&1.status == :effective))
        |> Map.new(&{&1.key, &1.mode_or_value})
      end

    effective_refs =
      candidates
      |> Enum.filter(&(&1.status == :effective))
      |> then(fn refs ->
        if health_open?, do: refs, else: refs
      end)

    result = %{
      "schema_version" => "conveyor.effective_capability_set@1",
      "adapter" => adapter,
      "declared_claim_refs" => refs_for(effective_refs, "declared"),
      "probe_claim_refs" => refs_for(effective_refs, "probed"),
      "observed_claim_refs" => refs_for(effective_refs, "observed"),
      "excluded_or_degraded_claims" => exclusions(candidates, health_open?),
      "effective_capabilities" => effective_capabilities,
      "derived_at" => derived_at,
      "capability_set_digest" => nil
    }

    %{result | "capability_set_digest" => digest(result)}
  end

  @spec max_autonomy(map(), keyword()) :: String.t()
  def max_autonomy(effective_set, opts \\ []) when is_map(effective_set) do
    policy = Keyword.get(opts, :policy, %{})
    admission_permit = Keyword.get(opts, :admission_permit, %{valid?: false})

    if permit_valid?(admission_permit) do
      effective_set
      |> adapter_capability_ceiling()
      |> min_level(policy_level(policy))
      |> min_level(permit_level(admission_permit))
    else
      "L0"
    end
  end

  defp candidate(key, claims, policy) do
    by_source = Map.new(claims, &{value(&1, "source"), &1})
    missing_sources = Enum.reject(@sources, &Map.has_key?(by_source, &1))
    allowed? = allowed_capability?(policy, key)
    values = by_source |> Map.values() |> Enum.map(&value(&1, "mode_or_value")) |> Enum.uniq()

    cond do
      missing_sources != [] ->
        candidate_result(
          key,
          by_source,
          :excluded,
          "missing_#{List.first(missing_sources)}_claim"
        )

      not allowed? ->
        candidate_result(key, by_source, :excluded, "policy_excluded")

      length(values) != 1 ->
        candidate_result(key, by_source, :excluded, "claim_value_mismatch")

      true ->
        candidate_result(key, by_source, :effective, nil, List.first(values))
    end
  end

  defp candidate_result(key, by_source, status, reason, mode_or_value \\ nil) do
    %{
      key: key,
      status: status,
      reason: reason,
      mode_or_value: mode_or_value,
      refs: Map.new(@sources, &{&1, value(by_source[&1], "evidence_ref")})
    }
  end

  defp refs_for(candidates, source) do
    candidates
    |> Enum.map(& &1.refs[source])
    |> Enum.reject(&is_nil/1)
    |> Enum.sort()
  end

  defp exclusions(candidates, health_open?) do
    candidate_exclusions =
      candidates
      |> Enum.filter(&(&1.status != :effective))
      |> Enum.map(&"#{&1.key}:#{&1.reason}")

    if health_open? do
      ["adapter_health:open" | candidate_exclusions]
    else
      candidate_exclusions
    end
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp allowed_capability?(policy, key) do
    case value(policy, :allowed_capabilities) do
      nil -> true
      :all -> true
      allowed -> key in List.wrap(allowed)
    end
  end

  defp adapter_capability_ceiling(effective_set) do
    capabilities = value(effective_set, "effective_capabilities") || %{}

    %{
      streaming_events: Map.get(capabilities, "streaming_events", false),
      pre_exec_command_policy: Map.get(capabilities, "pre_exec_command_policy", false),
      cancellation: Map.get(capabilities, "cancellation", "none"),
      diff_capture: Map.get(capabilities, "diff_capture", "adapter_reported"),
      cost_reporting: Map.get(capabilities, "cost_reporting", "none"),
      mcp_support: Map.get(capabilities, "mcp_support", false),
      slash_commands_enabled: Map.get(capabilities, "slash_commands_enabled", false),
      structured_output: Map.get(capabilities, "structured_output", false),
      session_resume: Map.get(capabilities, "session_resume", false),
      known_limitations: []
    }
    |> Capabilities.new!()
    |> Capabilities.autonomy_ceiling()
  end

  defp permit_valid?(permit), do: value(permit, :valid?) == true or value(permit, :valid) == true
  defp policy_level(policy), do: value(policy, :max_autonomy) || "L0"
  defp permit_level(permit), do: value(permit, :max_autonomy) || "L0"

  defp min_level(left, right) do
    if level_rank(left) <= level_rank(right), do: left, else: right
  end

  defp level_rank("L" <> level), do: String.to_integer(level)
  defp level_rank(level) when is_integer(level), do: level
  defp level_rank(_level), do: 0

  defp digest(result) do
    result
    |> Map.delete("capability_set_digest")
    |> canonical()
    |> Jason.encode!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
    |> then(&"sha256:#{&1}")
  end

  defp canonical(map) when is_map(map) do
    map
    |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
    |> Map.new(fn {key, value} -> {key, canonical(value)} end)
  end

  defp canonical(values) when is_list(values), do: Enum.map(values, &canonical/1)
  defp canonical(value), do: value

  defp value(nil, _key), do: nil
  defp value(map, key), do: Map.get(map, key) || Map.get(map, to_string(key))
end
