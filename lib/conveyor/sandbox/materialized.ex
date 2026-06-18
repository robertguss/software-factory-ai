defmodule Conveyor.Sandbox.Materialized do
  @moduledoc """
  Runtime handle for a materialized sandbox workspace.
  """

  alias Conveyor.Factory.WorkspaceMaterialization

  @type t :: %__MODULE__{
          workspace: WorkspaceMaterialization.t(),
          path: String.t(),
          root_path: String.t(),
          container_id: String.t() | nil,
          image_ref: String.t()
        }

  @enforce_keys [:workspace, :path, :root_path, :image_ref]
  defstruct [:workspace, :path, :root_path, :container_id, :image_ref]
end
