defmodule Conveyor.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      ConveyorWeb.Telemetry,
      Conveyor.Repo,
      {DNSCluster, query: Application.get_env(:conveyor, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Conveyor.PubSub},
      {Oban, Application.fetch_env!(:conveyor, Oban)},
      ConveyorWeb.Endpoint,
      Conveyor.Conductor.Supervisor
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Conveyor.Supervisor]

    with {:ok, _pid} = ok <- Supervisor.start_link(children, opts) do
      maybe_enqueue_boot_reconcile()
      ok
    end
  end

  # M6: on boot, resume runs interrupted by a crash (deploy, OOM, host reboot). Disabled in
  # test (`enqueue_boot_reconcile: false`) so the suite isn't perturbed by a boot job.
  defp maybe_enqueue_boot_reconcile do
    if Application.get_env(:conveyor, :enqueue_boot_reconcile, true) do
      Conveyor.Jobs.ReconcileInterruptedRuns.new(%{}) |> Oban.insert()
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ConveyorWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
