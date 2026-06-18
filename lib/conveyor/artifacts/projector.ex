defmodule Conveyor.Artifacts.Projector do
  @moduledoc """
  Behaviour and facade for regenerating run artifact projections.

  Postgres remains the source of truth. Projector backends produce read-only
  artifact trees from database metadata and content-addressed blobs.
  """

  use Conveyor.Conductor.Child

  alias Conveyor.Factory.RunAttempt

  defmodule Result do
    @moduledoc false

    @type t :: %__MODULE__{
            run_attempt_id: String.t(),
            projection_path: String.t(),
            artifact_count: non_neg_integer(),
            manifest_sha256: String.t(),
            bundle_root_sha256: String.t()
          }

    defstruct [
      :run_attempt_id,
      :projection_path,
      :artifact_count,
      :manifest_sha256,
      :bundle_root_sha256
    ]
  end

  @type backend :: module()

  @callback project_run!(struct(), keyword()) :: Result.t()

  @spec project_run!(struct(), keyword()) :: Result.t()
  def project_run!(%RunAttempt{} = run_attempt, opts \\ []) do
    backend = backend!(opts)
    backend.project_run!(run_attempt, Keyword.delete(opts, :backend))
  end

  @spec configured_backend() :: backend()
  def configured_backend do
    Application.get_env(:conveyor, :artifact_projector_backend, __MODULE__.LocalDisk)
  end

  defp backend!(opts) do
    backend = Keyword.get(opts, :backend, configured_backend())

    unless is_atom(backend) and Code.ensure_loaded?(backend) and
             function_exported?(backend, :project_run!, 2) do
      raise ArgumentError, "artifact projector backend must export project_run!/2"
    end

    backend
  end
end
