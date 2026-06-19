defmodule Conveyor.Qualification.Grants do
  @moduledoc """
  Pure P15-B8 grant issuance projections.

  A `QualificationGrant` is immutable evidence about a supported scope. The
  `AdmissionPermit` and `PermitCheckpoint` are derived current-authority
  projections for one effectful run boundary.
  """

  @default_invalidation_triggers ["policy_digest_changed", "scope_digest_changed"]
  @default_digest "sha256:0000000000000000000000000000000000000000000000000000000000000000"

  @spec issue(map()) :: {:ok, map()} | {:deny, map()}
  def issue(input) when is_map(input) do
    reasons = denial_reasons(input)

    if reasons == [] do
      {:ok, build_issue(input)}
    else
      {:deny, %{reasons: reasons}}
    end
  end

  defp denial_reasons(input) do
    []
    |> require_gate_passed(value(input, :gate_result, %{}))
    |> require_lattice_passed(value(input, :scope_lattice, %{}))
    |> require_scope_covered(
      value(input, :requested_scope, %{}),
      value(input, :supported_scope, %{})
    )
    |> Enum.reverse()
  end

  defp require_gate_passed(reasons, gate_result) do
    if value(gate_result, :status) in [:passed, "passed"],
      do: reasons,
      else: [:gate_not_passed | reasons]
  end

  defp require_lattice_passed(reasons, lattice) do
    if value(lattice, :worst_required_stratum_result) == "pass" do
      reasons
    else
      [:scope_lattice_not_passed | reasons]
    end
  end

  defp require_scope_covered(reasons, requested_scope, supported_scope) do
    if scope_covers?(stringify_map(supported_scope), stringify_map(requested_scope)) do
      reasons
    else
      [:scope_not_covered | reasons]
    end
  end

  defp scope_covers?(supported_scope, requested_scope) do
    Enum.all?(requested_scope, fn {key, requested} ->
      Map.get(supported_scope, key) in [requested, "*"]
    end)
  end

  defp build_issue(input) do
    project_id = value(input, :project_id)
    supported_scope = stringify_map(value(input, :supported_scope, %{}))
    gate_result = value(input, :gate_result, %{})
    lattice = build_lattice(input, supported_scope)
    grant = build_grant(input, project_id, supported_scope, lattice, gate_result)
    permit = build_permit(input, project_id, grant)
    checkpoint = build_checkpoint(input, permit)

    %{
      grant: grant,
      scope_lattice: lattice,
      admission_permit: permit,
      permit_checkpoint: checkpoint
    }
  end

  defp build_lattice(input, supported_scope) do
    lattice = stringify_map(value(input, :scope_lattice, %{}))
    scope_digest = digest(supported_scope)

    lattice
    |> Map.put("schema_version", "conveyor.qualification_scope_lattice@1")
    |> Map.put_new(
      "id",
      "qualification_scope_lattice:" <> String.replace_prefix(scope_digest, "sha256:", "sha256:")
    )
    |> Map.put("scope_ref", scope_ref(supported_scope))
    |> Map.put("scope_digest", scope_digest)
    |> Map.put_new("direct_evidence_strata", [])
    |> Map.put_new("inherited_evidence_strata", [])
    |> Map.put_new("supporting_evidence_strata", [])
    |> Map.put_new("inheritance_rule_refs", [])
    |> Map.put_new("inheritance_default", "none")
    |> Map.put_new("unassessed_strata", [])
  end

  defp build_grant(input, project_id, supported_scope, lattice, gate_result) do
    scope_digest = Map.fetch!(lattice, "scope_digest")
    issued_at = value(input, :issued_at, now())
    expires_at = value(input, :expires_at)

    base = %{
      "schema_version" => "conveyor.qualification_grant@1",
      "project_id" => project_id,
      "qualification_gate_run_id" =>
        value(input, :qualification_gate_run_id, "qualification-gate-local"),
      "evidence_root_digest" => value(gate_result, :evidence_root_digest, @default_digest),
      "scope" => supported_scope,
      "scope_ref" => scope_ref(supported_scope),
      "scope_digest" => scope_digest,
      "adapter_class" => Map.get(supported_scope, "adapter", "unspecified"),
      "agent_class" => value(input, :agent_class, "codex"),
      "archetype_class" => Map.get(supported_scope, "archetype", "unspecified"),
      "change_class" => value(input, :change_class, "unspecified"),
      "toolchain_class" => value(input, :toolchain_class, "mix"),
      "risk_class" => value(input, :risk_class, "local_dev"),
      "policy_digest" => value(input, :policy_digest, @default_digest),
      "environment_digest" => value(input, :environment_digest, @default_digest),
      "deployment_digest" => value(input, :deployment_digest, @default_digest),
      "max_autonomy" => value(input, :max_autonomy, "local_dev"),
      "success_rate_bands" => value(input, :success_rate_bands, []),
      "limitations" => value(input, :limitations, []),
      "waiver_refs" => value(input, :waiver_refs, []),
      "issued_at" => issued_at,
      "invalidation_triggers" =>
        value(input, :invalidation_triggers, @default_invalidation_triggers),
      "status" => "active"
    }

    base
    |> put_optional("expires_at", expires_at)
    |> then(&Map.put(&1, "id", "qualification_grant:" <> digest(&1)))
  end

  defp build_permit(input, project_id, grant) do
    issued_at = value(input, :issued_at, now())
    expires_at = value(input, :permit_expires_at, value(input, :expires_at, issued_at))

    permit =
      %{
        "schema_version" => "conveyor.admission_permit@1",
        "subject_kind" => value(input, :subject_kind, "project"),
        "subject_id" => value(input, :subject_id, project_id),
        "spec_digest" => value(input, :spec_digest, grant["scope_digest"]),
        "qualification_grant_id" => grant["id"],
        "effective_capability_set_digest" =>
          value(input, :effective_capability_set_digest, @default_digest),
        "authority_root_digests" =>
          value(input, :authority_root_digests, [grant["evidence_root_digest"]]),
        "policy_digest" => grant["policy_digest"],
        "environment_digest" => grant["environment_digest"],
        "budget_reservation_ids" => value(input, :budget_reservation_ids, []),
        "control_generation" => value(input, :control_generation, 0),
        "issued_at" => issued_at,
        "expires_at" => expires_at
      }

    permit
    |> Map.put("permit_digest", digest(permit))
    |> then(&Map.put(&1, "id", "admission_permit:" <> &1["permit_digest"]))
  end

  defp build_checkpoint(input, permit) do
    checkpoint =
      %{
        "schema_version" => "conveyor.permit_checkpoint@1",
        "admission_permit_id" => permit["id"],
        "subject_ref" => "#{permit["subject_kind"]}:#{permit["subject_id"]}",
        "station_run_id" => value(input, :station_run_id, "qualification-gate-local"),
        "checkpoint_kind" => value(input, :checkpoint_kind, "before_effectful_boundary"),
        "validated_inputs_digest" =>
          value(input, :validated_inputs_digest, permit["spec_digest"]),
        "result" => "valid",
        "reason_codes" => [],
        "policy_decision_id" => value(input, :policy_decision_id, "policy-decision-local"),
        "checked_at" => value(input, :checked_at, value(input, :issued_at, now())),
        "trace_id" => value(input, :trace_id, "qualification-gate-local")
      }

    Map.put(checkpoint, "id", "permit_checkpoint:" <> digest(checkpoint))
  end

  defp scope_ref(scope) do
    scope
    |> Enum.map(fn {key, value} -> "#{key}=#{value}" end)
    |> Enum.sort()
    |> Enum.join("|")
    |> then(&"qualification-scope:#{&1}")
  end

  defp put_optional(map, _key, nil), do: map
  defp put_optional(map, key, value), do: Map.put(map, key, value)

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
  defp stringify_value(value) when is_atom(value), do: Atom.to_string(value)
  defp stringify_value(value), do: value

  defp now, do: "1970-01-01T00:00:00Z"

  defp value(map, key, default \\ nil) do
    Map.get(map, key, Map.get(map, to_string(key), default))
  end
end
