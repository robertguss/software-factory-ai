defmodule Conveyor.Sandbox.NetworkPolicy do
  @moduledoc """
  Network policy helpers for sandbox containers.
  """

  @internal_hosts MapSet.new([
                    "0.0.0.0",
                    "::1",
                    "conductor",
                    "db",
                    "host.docker.internal",
                    "localhost",
                    "postgres"
                  ])

  @station_defaults %{
    scout: :none,
    implement: :none,
    verify: :none,
    gate: :none,
    canary: :none
  }
  @private_prefixes [
    "127.",
    "10.",
    "172.16.",
    "172.17.",
    "172.18.",
    "172.19.",
    "172.20.",
    "172.21.",
    "172.22.",
    "172.23.",
    "172.24.",
    "172.25.",
    "172.26.",
    "172.27.",
    "172.28.",
    "172.29.",
    "172.30.",
    "172.31.",
    "192.168."
  ]

  @type mode :: :none | :egress

  @spec default_for(atom() | String.t()) :: mode()
  def default_for(station) when is_binary(station) do
    station
    |> String.to_existing_atom()
    |> default_for()
  rescue
    ArgumentError -> :none
  end

  def default_for(station), do: Map.get(@station_defaults, station, :none)

  @spec docker_args(mode()) :: [String.t()]
  def docker_args(:none), do: ["--network", "none"]

  # ponytail: full outbound egress via Docker's default bridge — the minimum that lets a
  # coding agent reach its model API. Filesystem/env/non-root confinement is unaffected.
  # Upgrade path: an allowlist-via-proxy network (validate_egress_allowlist!/1 already
  # exists for it) to constrain egress to specific hosts.
  def docker_args(:egress), do: ["--network", "bridge"]

  @spec validate_egress_allowlist!([String.t()]) :: :ok
  def validate_egress_allowlist!(hosts) when is_list(hosts) do
    case Enum.filter(hosts, &internal_host?/1) do
      [] ->
        :ok

      blocked ->
        raise ArgumentError,
              "egress allowlist includes conductor/internal host(s): #{Enum.join(blocked, ", ")}"
    end
  end

  def validate_egress_allowlist!(_hosts) do
    raise ArgumentError, "egress allowlist must be a list"
  end

  @spec internal_host?(String.t()) :: boolean()
  def internal_host?(host) when is_binary(host) do
    normalized =
      host
      |> String.downcase()
      |> String.trim()

    MapSet.member?(@internal_hosts, normalized) or
      Enum.any?(@private_prefixes, &String.starts_with?(normalized, &1))
  end
end
