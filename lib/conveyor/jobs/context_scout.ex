defmodule Conveyor.Jobs.ContextScout do
  @moduledoc "Repository context scout worker skeleton."
  use Conveyor.Jobs.WorkerStub, queue: :conductor

  @spec run!(Conveyor.Factory.Slice.t() | Ecto.UUID.t(), keyword()) ::
          Conveyor.Factory.ContextPack.t()
  def run!(slice_or_id, opts \\ []), do: Conveyor.ContextScout.run!(slice_or_id, opts)
end
