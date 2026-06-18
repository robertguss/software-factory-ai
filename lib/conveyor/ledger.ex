defmodule Conveyor.Ledger do
  @moduledoc """
  Idempotent append-only writer for the Conveyor audit ledger.
  """

  use Conveyor.Conductor.Child

  alias Conveyor.Factory
  alias Conveyor.Factory.LedgerEvent

  @spec write!(map(), keyword()) :: struct() | {struct(), list()}
  def write!(attrs, opts \\ []) when is_map(attrs) do
    {:ok, event} = write(attrs, opts)
    event
  end

  @spec write(map(), keyword()) :: {:ok, struct() | {struct(), list()}}
  def write(attrs, opts \\ []) when is_map(attrs) do
    attrs = normalize_attrs(attrs)
    return_notifications? = Keyword.get(opts, :return_notifications?, false)

    case existing_event(attrs.idempotency_key, return_notifications?) do
      {:ok, nil} -> create_event(attrs, return_notifications?)
      {:ok, event} -> {:ok, event}
    end
  rescue
    error in Ash.Error.Invalid ->
      case existing_event(
             Map.get(attrs, :idempotency_key),
             Keyword.get(opts, :return_notifications?, false)
           ) do
        {:ok, nil} -> reraise error, __STACKTRACE__
        {:ok, event} -> {:ok, event}
      end
  end

  @spec tombstone!(map(), keyword()) :: struct() | {struct(), list()}
  def tombstone!(attrs, opts \\ []) when is_map(attrs) do
    actor = Map.fetch!(attrs, :actor)
    artifact_id = Map.fetch!(attrs, :artifact_id)
    idempotency_key = Map.fetch!(attrs, :idempotency_key)
    prior_sha256 = Map.fetch!(attrs, :prior_sha256)
    project_id = Map.fetch!(attrs, :project_id)
    reason = Map.fetch!(attrs, :reason)

    attrs
    |> Map.take([
      :slice_id,
      :run_attempt_id,
      :agent_session_id,
      :station_run_id,
      :trace_id,
      :span_id
    ])
    |> Map.merge(%{
      project_id: project_id,
      idempotency_key: idempotency_key,
      type: Map.get(attrs, :type, "artifact.deleted"),
      payload: %{
        "actor" => actor,
        "artifact_id" => artifact_id,
        "prior_sha256" => prior_sha256,
        "reason" => reason
      }
    })
    |> write!(opts)
  end

  defp create_event(attrs, return_notifications?) do
    event_attrs =
      attrs
      |> Map.put_new(:payload, %{})
      |> Map.put_new_lazy(:occurred_at, fn -> DateTime.utc_now(:microsecond) end)

    {:ok,
     Ash.create!(
       LedgerEvent,
       event_attrs,
       domain: Factory,
       return_notifications?: return_notifications?
     )}
  end

  defp existing_event(nil, _return_notifications?), do: {:ok, nil}

  defp existing_event(idempotency_key, true) do
    case find_existing_event(idempotency_key) do
      nil -> {:ok, nil}
      event -> {:ok, {event, []}}
    end
  end

  defp existing_event(idempotency_key, false), do: {:ok, find_existing_event(idempotency_key)}

  defp find_existing_event(idempotency_key) do
    LedgerEvent
    |> Ash.read!(domain: Factory)
    |> Enum.find(&(&1.idempotency_key == idempotency_key))
  end

  defp normalize_attrs(attrs) do
    attrs
    |> Map.new(fn
      {key, value} when is_binary(key) -> {String.to_existing_atom(key), value}
      {key, value} -> {key, value}
    end)
    |> Map.put_new(:payload, %{})
    |> Map.put_new_lazy(:occurred_at, fn -> DateTime.utc_now(:microsecond) end)
  end
end
