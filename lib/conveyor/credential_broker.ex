defmodule Conveyor.CredentialBroker do
  @moduledoc """
  Issues and revokes short-lived credential leases without persisting secret values.
  """

  alias Conveyor.Factory
  alias Conveyor.Factory.CredentialLease
  alias Conveyor.Factory.RunSpec
  alias Conveyor.Factory.StationRun

  defmodule IssuedLease do
    @moduledoc false

    @type t :: %__MODULE__{
            lease: CredentialLease.t(),
            env: map()
          }

    @enforce_keys [:lease, :env]
    defstruct [:lease, :env]
  end

  @spec issue!(RunSpec.t(), String.t(), keyword()) :: IssuedLease.t()
  def issue!(%RunSpec{} = run_spec, provider, opts \\ []) when is_binary(provider) do
    env = opts |> Keyword.get(:env, %{}) |> normalize_env!()
    env_keys = opts |> Keyword.get(:env_keys, Map.keys(env)) |> Enum.sort()
    allowed_env_keys = Keyword.get(opts, :allowed_env_keys, env_keys)

    validate_env_keys!(env_keys, allowed_env_keys)

    issued_at = Keyword.get_lazy(opts, :issued_at, fn -> DateTime.utc_now(:microsecond) end)
    ttl_seconds = Keyword.get(opts, :ttl_seconds, 900)

    lease =
      Ash.create!(
        CredentialLease,
        %{
          run_spec_id: run_spec.id,
          station_run_id: station_run_id(Keyword.get(opts, :station_run)),
          provider: provider,
          env_keys: env_keys,
          scope: Keyword.get(opts, :scope, "run_spec:#{run_spec.id}"),
          issued_at: issued_at,
          expires_at: DateTime.add(issued_at, ttl_seconds, :second),
          status: :active
        },
        domain: Factory
      )

    %IssuedLease{lease: lease, env: Map.take(env, env_keys)}
  end

  @spec revoke!(CredentialLease.t(), keyword()) :: CredentialLease.t()
  def revoke!(%CredentialLease{} = lease, opts \\ []) do
    Ash.update!(
      lease,
      %{
        revoked_at: Keyword.get_lazy(opts, :revoked_at, fn -> DateTime.utc_now(:microsecond) end),
        status: Keyword.get(opts, :status, :revoked)
      },
      domain: Factory
    )
  end

  @spec revoke_for_run_spec!(RunSpec.t() | Ecto.UUID.t(), keyword()) :: [CredentialLease.t()]
  def revoke_for_run_spec!(run_spec_or_id, opts \\ []) do
    run_spec_id = id_for(run_spec_or_id)

    CredentialLease
    |> Ash.read!(domain: Factory)
    |> Enum.filter(&(&1.run_spec_id == run_spec_id and &1.status in [:issued, :active]))
    |> Enum.map(&revoke!(&1, opts))
  end

  @spec revoke_for_station_run!(StationRun.t() | Ecto.UUID.t(), keyword()) :: [
          CredentialLease.t()
        ]
  def revoke_for_station_run!(station_run_or_id, opts \\ []) do
    station_run_id = id_for(station_run_or_id)

    CredentialLease
    |> Ash.read!(domain: Factory)
    |> Enum.filter(&(&1.station_run_id == station_run_id and &1.status in [:issued, :active]))
    |> Enum.map(&revoke!(&1, opts))
  end

  @spec expire_stale!(keyword()) :: [CredentialLease.t()]
  def expire_stale!(opts \\ []) do
    now = Keyword.get_lazy(opts, :now, fn -> DateTime.utc_now(:microsecond) end)

    CredentialLease
    |> Ash.read!(domain: Factory)
    |> Enum.filter(
      &(&1.status in [:issued, :active] and DateTime.compare(&1.expires_at, now) != :gt)
    )
    |> Enum.map(&revoke!(&1, revoked_at: now, status: :expired))
  end

  defp normalize_env!(env) when is_map(env) do
    Map.new(env, fn
      {key, value} when is_binary(key) and is_binary(value) -> {key, value}
      {_key, _value} -> raise ArgumentError, "credential env must be string keys and values"
    end)
  end

  defp normalize_env!(_env), do: raise(ArgumentError, "credential env must be a map")

  defp validate_env_keys!(env_keys, allowed_env_keys) do
    denied = env_keys -- allowed_env_keys

    if denied != [] do
      raise ArgumentError,
            "credential env keys are not allowed by policy: #{Enum.join(denied, ", ")}"
    end
  end

  defp station_run_id(nil), do: nil
  defp station_run_id(%StationRun{id: id}), do: id
  defp station_run_id(id) when is_binary(id), do: id

  defp id_for(%{id: id}), do: id
  defp id_for(id) when is_binary(id), do: id
end
