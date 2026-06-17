defmodule Conveyor.Factory.Validations.StationPlan do
  @moduledoc false

  use Ash.Resource.Validation

  alias Ash.Error.Changes.InvalidAttribute

  @impl true
  def validate(changeset, _opts, _context) do
    station_plan = Ash.Changeset.get_attribute(changeset, :station_plan)
    run_spec_sha256 = Ash.Changeset.get_attribute(changeset, :run_spec_sha256)

    case Conveyor.Factory.StationPlan.validate(station_plan, run_spec_sha256) do
      :ok ->
        :ok

      {:error, message} ->
        {:error, InvalidAttribute.exception(field: :station_plan, message: message)}
    end
  end
end
