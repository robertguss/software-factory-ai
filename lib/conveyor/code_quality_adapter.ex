defmodule Conveyor.CodeQualityAdapter do
  @moduledoc """
  Behaviour and runner for read-only code-quality adapters.
  """

  alias Conveyor.Artifacts.BlobStore
  alias Conveyor.CodeQualityAdapter.Result
  alias Conveyor.Factory
  alias Conveyor.Factory.CodeQualityRun
  alias Conveyor.Factory.Project

  @callback adapter_name() :: String.t()
  @callback adapter_contract() :: map()
  @callback scan(Project.t(), keyword()) :: Result.t()

  @spec run!(Project.t() | Ecto.UUID.t(), module(), keyword()) :: CodeQualityRun.t()
  def run!(project_or_id, adapter_module, opts \\ []) do
    project = project!(project_or_id)
    result = adapter_module.scan(project, opts) |> Result.validate!()
    result_ref = write_result!(result, opts)

    Ash.create!(
      CodeQualityRun,
      %{
        project_id: project.id,
        run_attempt_id: Keyword.get(opts, :run_attempt_id),
        adapter: result.adapter,
        profile: result.profile,
        baseline_ref: Keyword.get(opts, :baseline_ref),
        result_ref: result_ref,
        findings_summary: result.findings_summary,
        new_high_risk_findings: result.new_high_risk_findings,
        status: result.status
      },
      domain: Factory
    )
  end

  @spec result_blob!(Result.t(), keyword()) :: BlobStore.Blob.t()
  def result_blob!(%Result{} = result, opts \\ []) do
    result
    |> Result.to_map()
    |> Jason.encode!(pretty: true)
    |> BlobStore.write!(opts)
  end

  defp write_result!(result, opts) do
    result
    |> result_blob!(opts)
    |> Map.fetch!(:ref)
  end

  defp project!(%Project{} = project), do: project

  defp project!(project_id) when is_binary(project_id) do
    Project
    |> Ash.read!(domain: Factory)
    |> Enum.find(&(&1.id == project_id)) ||
      raise ArgumentError, "project #{project_id} was not found"
  end
end
