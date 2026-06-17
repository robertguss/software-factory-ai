defmodule Conveyor.Telemetry do
  @moduledoc "Conductor trace, metric, and log emission service skeleton."
  use Conveyor.Conductor.Child

  alias Conveyor.Telemetry.Conventions

  @spec emit_metric([atom()], map(), map()) ::
          :ok | {:error, {:disallowed_metric_dimensions, [String.t()]}}
  def emit_metric(event_name, measurements, metadata \\ %{})
      when is_list(event_name) and is_map(measurements) and is_map(metadata) do
    with :ok <- Conventions.validate_metric_dimensions(metadata) do
      :telemetry.execute(event_name, measurements, metadata)
      :ok
    end
  end
end
