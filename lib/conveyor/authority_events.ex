defmodule Conveyor.AuthorityEvents do
  @moduledoc """
  AuthorityEvent envelope helpers.
  """

  alias Conveyor.Factory.AuthorityEvent

  @provider_safe_trace_keys MapSet.new(~w(trace_id span_id correlation_id traceparent))

  @spec to_cloud_event(AuthorityEvent.t()) :: map()
  def to_cloud_event(%AuthorityEvent{} = event) do
    %{
      "specversion" => "1.0",
      "id" => event.event_id,
      "source" => "/conveyor/authority/#{event.stream_id}",
      "type" => event.event_type,
      "subject" => subject(event.subject_ref),
      "time" => DateTime.to_iso8601(event.committed_at),
      "datacontenttype" => "application/json",
      "data" => %{
        "stream_id" => event.stream_id,
        "stream_version" => event.stream_version,
        "subject_ref" => event.subject_ref,
        "payload_ref" => event.payload_ref,
        "fencing_token" => event.fencing_token,
        "policy_decision_id" => event.policy_decision_id,
        "trace_context" => provider_safe_trace_context(event.trace_context || %{})
      }
    }
  end

  @spec provider_safe_trace_context(map()) :: map()
  def provider_safe_trace_context(context) when is_map(context) do
    context
    |> Enum.filter(fn {key, _value} ->
      MapSet.member?(@provider_safe_trace_keys, to_string(key))
    end)
    |> Map.new(fn {key, value} -> {to_string(key), value} end)
  end

  defp subject(%{"kind" => kind, "id_or_key" => id}), do: "#{kind}:#{id}"
  defp subject(%{kind: kind, id_or_key: id}), do: "#{kind}:#{id}"
  defp subject(subject_ref), do: inspect(subject_ref)
end
