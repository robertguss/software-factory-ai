defmodule Conveyor.Artifacts.ArtifactStore do
  @moduledoc """
  Artifact store backend contract.
  """

  @callback new(keyword()) :: struct()
  @callback put!(struct(), binary()) :: Conveyor.Artifacts.ArtifactStore.Address.t()
  @callback get!(struct(), Conveyor.Artifacts.ArtifactStore.Address.t()) :: binary()
  @callback head!(struct(), Conveyor.Artifacts.ArtifactStore.Address.t()) :: map()
  @callback copy!(struct(), Conveyor.Artifacts.ArtifactStore.Address.t(), keyword()) ::
              Conveyor.Artifacts.ArtifactStore.Address.t()
  @callback secure_delete!(struct(), Conveyor.Artifacts.ArtifactStore.Address.t()) :: :ok
  @callback list_segments!(struct()) :: [Conveyor.Artifacts.ArtifactStore.Address.t()]

  @required_callbacks ~w(new put! get! head! copy! secure_delete! list_segments!)a

  @spec assert_backend!(module()) :: :ok
  def assert_backend!(module) when is_atom(module) do
    Code.ensure_loaded!(module)

    missing =
      Enum.reject(@required_callbacks, fn function ->
        function_exported?(module, function, arity(function))
      end)

    case missing do
      [] ->
        :ok

      callbacks ->
        raise ArgumentError, "artifact backend missing callbacks: #{inspect(callbacks)}"
    end
  end

  defp arity(:new), do: 1
  defp arity(:put!), do: 2
  defp arity(:get!), do: 2
  defp arity(:head!), do: 2
  defp arity(:copy!), do: 3
  defp arity(:secure_delete!), do: 2
  defp arity(:list_segments!), do: 1
end
