defmodule Conveyor.Cassettes do
  @moduledoc """
  Artifact-shaped CassetteSeries and AgentCassette builders.

  These helpers keep the first cassette implementation hermetic: callers can
  persist the returned maps in the artifact store or a later resource layer.
  """

  alias Conveyor.Security.Redactor

  @spec new_series!(map()) :: map()
  def new_series!(attrs) when is_map(attrs) do
    series =
      %{
        "schema_version" => "conveyor.cassette_series@1",
        "spec_kind" => required_string(attrs, :spec_kind),
        "spec_digest" => required_string(attrs, :spec_digest),
        "role" => required_string(attrs, :role),
        "adapter" => required_string(attrs, :adapter),
        "agent_profile_snapshot_digest" => required_string(attrs, :agent_profile_snapshot_digest),
        "capability_snapshot_digest" => required_string(attrs, :capability_snapshot_digest),
        "generation_environment_fingerprint_digest" =>
          required_string(attrs, :generation_environment_fingerprint_digest),
        "generation_freshness_digest" => required_string(attrs, :generation_freshness_digest),
        "created_at" => required_string(attrs, :created_at)
      }

    Map.put(series, "id", "cassette_series:#{digest(series)}")
  end

  @spec record(map(), keyword()) :: {:ok, map()} | {:error, map()}
  def record(series, opts) when is_map(series) and is_list(opts) do
    base = cassette_base(series, opts)

    with :ok <- require_integrity(opts),
         {:ok, redaction} <- redact_outputs(Keyword.get(opts, :primary_outputs, []), opts) do
      {:ok,
       base
       |> Map.merge(redaction_fields(redaction))
       |> Map.put("seal_status", "sealed")}
    else
      {:error, %Redactor.Result{} = blocked} ->
        {:error,
         base
         |> Map.merge(redaction_fields(blocked))
         |> Map.put("seal_status", "rejected")
         |> Map.put("invalidation_reason", "redaction_blocked")}

      {:error, reason} ->
        {:error,
         base
         |> Map.merge(empty_redaction_fields())
         |> Map.put("seal_status", "rejected")
         |> Map.put("invalidation_reason", Atom.to_string(reason))}
    end
  end

  defp cassette_base(series, opts) do
    recording_no = Keyword.fetch!(opts, :recording_no)
    provider = Keyword.get(opts, :provider, %{})

    %{
      "schema_version" => "conveyor.agent_cassette@1",
      "id" => "agent_cassette:#{digest(%{series_id: series["id"], recording_no: recording_no})}",
      "cassette_series_id" => series["id"],
      "recording_no" => recording_no,
      "provider_request_id" => value(provider, :request_id),
      "provider_model_id" => value(provider, :model_id),
      "provider_model_revision" => value(provider, :model_revision),
      "provider_identity_confidence" => provider_identity_confidence(provider),
      "provider_parameters" => Keyword.get(opts, :provider_parameters, %{}),
      "agent_event_stream" => Keyword.get(opts, :agent_event_stream, []),
      "tool_transcript" => Keyword.get(opts, :tool_transcript, []),
      "primary_output_refs" => output_refs(Keyword.get(opts, :primary_outputs, [])),
      "patch_set_digest" => Keyword.get(opts, :patch_set_digest),
      "recorded_diagnostics_ref" => Keyword.get(opts, :recorded_diagnostics_ref),
      "retention_class" => Keyword.get(opts, :retention_class, "diagnostic"),
      "expires_at" => Keyword.get(opts, :expires_at),
      "recorded_at" => Keyword.fetch!(opts, :recorded_at)
    }
  end

  defp require_integrity(opts) do
    cond do
      Keyword.get(opts, :agent_event_stream, []) == [] -> {:error, :missing_agent_event_stream}
      not is_list(Keyword.get(opts, :tool_transcript, [])) -> {:error, :invalid_tool_transcript}
      true -> :ok
    end
  end

  defp redact_outputs(outputs, opts) do
    policy = Keyword.get(opts, :redaction_policy, :redact)
    results = Enum.map(outputs, &Redactor.redact!(&1, source: "agent_cassette", policy: policy))

    case Enum.find(results, & &1.blocked?) do
      nil ->
        {:ok,
         %{
           outputs: Enum.map(results, & &1.content),
           findings: Enum.flat_map(results, & &1.findings),
           sensitivity: aggregate_sensitivity(results),
           raw_sha256: digest(outputs),
           redacted_sha256: digest(Enum.map(results, & &1.content))
         }}

      blocked ->
        {:error, blocked}
    end
  end

  defp redaction_fields(%Redactor.Result{} = result) do
    %{
      "primary_outputs" => [result.content],
      "redaction_report" => %{
        "findings" => result.findings,
        "sensitivity" => Atom.to_string(result.sensitivity),
        "raw_sha256" => result.raw_sha256,
        "redacted_sha256" => result.redacted_sha256
      },
      "redaction_report_ref" => result.redacted_sha256
    }
  end

  defp redaction_fields(redaction) do
    %{
      "primary_outputs" => redaction.outputs,
      "redaction_report" => %{
        "findings" => redaction.findings,
        "sensitivity" => Atom.to_string(redaction.sensitivity),
        "raw_sha256" => redaction.raw_sha256,
        "redacted_sha256" => redaction.redacted_sha256
      },
      "redaction_report_ref" => redaction.redacted_sha256
    }
  end

  defp empty_redaction_fields do
    %{
      "primary_outputs" => [],
      "redaction_report" => %{"findings" => [], "sensitivity" => "unscanned"},
      "redaction_report_ref" => nil
    }
  end

  defp aggregate_sensitivity(results) do
    cond do
      Enum.any?(results, &(&1.sensitivity == :quarantined)) -> :quarantined
      Enum.any?(results, &(&1.sensitivity == :redacted)) -> :redacted
      true -> :internal
    end
  end

  defp provider_identity_confidence(provider) do
    cond do
      present?(value(provider, :model_id)) and present?(value(provider, :model_revision)) ->
        "exact"

      present?(value(provider, :model_id)) ->
        "declared_only"

      present?(value(provider, :model_family)) ->
        "family_only"

      true ->
        "unknown"
    end
  end

  defp output_refs(outputs), do: Enum.map(outputs, &"sha256:#{digest(&1)}")

  defp required_string(attrs, key) do
    case value(attrs, key) do
      value when is_atom(value) -> Atom.to_string(value)
      value when is_binary(value) and value != "" -> value
      _other -> raise ArgumentError, "#{key} must be present"
    end
  end

  defp present?(value), do: is_binary(value) and value != ""

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

  defp value(map, key), do: Map.get(map, key) || Map.get(map, to_string(key))
end
