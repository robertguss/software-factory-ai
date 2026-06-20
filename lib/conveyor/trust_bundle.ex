defmodule Conveyor.TrustBundle do
  @moduledoc """
  Builds and emits DSSE-shaped trust bundles for gate verdicts.
  """

  alias Conveyor.Factory
  alias Conveyor.Factory.Artifact
  alias Conveyor.Factory.GateResult
  alias Conveyor.Factory.RunAttempt
  alias Conveyor.Factory.RunSpec

  @schema_version "conveyor.trust_bundle@1"
  @payload_type "application/vnd.conveyor.trust_bundle.payload+json"
  @media_type "application/vnd.dsse.envelope+json"

  @spec build(map()) :: map()
  def build(input) when is_map(input) do
    payload =
      %{
        "schema_version" => "conveyor.trust_bundle.payload@1",
        "run_attempt_id" => required(input, :run_attempt_id),
        "run_spec_sha256" => required(input, :run_spec_sha256),
        "gate_result_id" => required(input, :gate_result_id),
        "gate_result_sha256" => required(input, :gate_result_sha256),
        "verdict" => input |> required(:verdict) |> to_string(),
        "provenance_edge_sha256s" => list(value(input, :provenance_edge_sha256s, [])),
        "created_at" => required(input, :created_at)
      }

    payload_json = Conveyor.CanonicalJson.encode(payload)
    payload_sha256 = Conveyor.CanonicalJson.digest(payload)

    bundle = %{
      "schema_version" => @schema_version,
      "payload_sha256" => payload_sha256,
      "signature_status" => "unsigned_local",
      "dsse" => %{
        "payloadType" => @payload_type,
        "payload" => Base.encode64(payload_json),
        "signatures" => [
          %{
            "keyid" => "unsigned-local",
            "sig" => Base.encode64("unsigned-local:#{payload_sha256}")
          }
        ]
      }
    }

    Map.put(bundle, "bundle_sha256", Conveyor.CanonicalJson.digest(bundle))
  end

  @spec emit!(map(), GateResult.t(), keyword()) :: map()
  def emit!(context, %GateResult{} = gate_result, opts \\ []) when is_map(context) do
    run_attempt = run_attempt!(context)
    run_spec = run_spec!(context, run_attempt)
    created_at = Keyword.get_lazy(opts, :created_at, fn -> DateTime.utc_now(:microsecond) end)

    bundle =
      build(%{
        run_attempt_id: run_attempt.id,
        run_spec_sha256: run_spec.run_spec_sha256,
        gate_result_id: gate_result.id,
        gate_result_sha256: gate_result_sha256(gate_result),
        verdict: verdict(gate_result),
        provenance_edge_sha256s:
          opts
          |> Keyword.get(:provenance_edges, [])
          |> Enum.map(& &1.edge_sha256),
        created_at: created_at(created_at)
      })

    content = Conveyor.CanonicalJson.encode(bundle)
    sha256 = sha256(content)

    artifact =
      Ash.create!(
        Artifact,
        %{
          run_attempt_id: run_attempt.id,
          kind: "trust-bundle",
          media_type: @media_type,
          projection_path:
            "artifacts/trust-bundles/#{run_attempt.id}-#{gate_result.id}.dsse.json",
          blob_ref: "urn:sha256:#{sha256}",
          sha256: sha256,
          size_bytes: byte_size(content),
          subject_kind: "gate_result",
          producer: "gate.finalizer",
          schema_version: @schema_version,
          sensitivity: :internal
        },
        domain: Factory
      )

    %{artifact: artifact, bundle: bundle}
  end

  defp gate_result_sha256(gate_result) do
    Conveyor.CanonicalJson.digest(%{
      "id" => gate_result.id,
      "passed" => gate_result.passed,
      "stages" => gate_result.stages,
      "gate_version" => gate_result.gate_version,
      "gate_code_sha256" => gate_result.gate_code_sha256,
      "policy_sha256" => gate_result.policy_sha256,
      "contract_lock_sha256" => gate_result.contract_lock_sha256,
      "canary_suite_version" => gate_result.canary_suite_version
    })
  end

  defp run_attempt!(context) do
    value(context, :run_attempt) || get_by_id!(RunAttempt, value(context, :run_attempt_id))
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

  defp verdict(%GateResult{passed: true}), do: :passed
  defp verdict(%GateResult{passed: false}), do: :failed

  defp created_at(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp created_at(value), do: value

  defp required(map, key) do
    value(map, key) || raise ArgumentError, "#{key} is required"
  end

  defp value(map, key, default \\ nil) when is_map(map),
    do: Map.get(map, key, Map.get(map, to_string(key), default))

  defp list(nil), do: []
  defp list(values) when is_list(values), do: values
  defp list(value), do: [value]

  defp sha256(content), do: :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
end
