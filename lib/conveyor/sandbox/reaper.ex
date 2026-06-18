defmodule Conveyor.Sandbox.Reaper do
  @moduledoc "Sandbox cleanup and orphan reaping service skeleton."
  use Conveyor.Conductor.Child

  alias Conveyor.Factory
  alias Conveyor.Factory.WorkspaceMaterialization
  alias Conveyor.Sandbox.WorkspaceCleanup

  defmodule Result do
    @moduledoc false

    @type t :: %__MODULE__{
            deleted: non_neg_integer(),
            preserved: non_neg_integer(),
            failed: non_neg_integer()
          }

    defstruct deleted: 0, preserved: 0, failed: 0
  end

  @spec reap!(keyword()) :: Result.t()
  def reap!(opts \\ []) do
    WorkspaceMaterialization
    |> Ash.read!(domain: Factory)
    |> Enum.filter(&(&1.cleanup_status == :pending))
    |> Enum.reduce(%Result{}, fn workspace, result ->
      workspace
      |> WorkspaceCleanup.cleanup(Keyword.put_new(opts, :failed?, true))
      |> update_result(result)
    end)
  end

  defp update_result({:ok, %WorkspaceMaterialization{cleanup_status: :deleted}}, result) do
    %{result | deleted: result.deleted + 1}
  end

  defp update_result({:ok, %WorkspaceMaterialization{cleanup_status: :preserved}}, result) do
    %{result | preserved: result.preserved + 1}
  end

  defp update_result({:error, _reason}, result), do: %{result | failed: result.failed + 1}
end
