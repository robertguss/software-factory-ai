defmodule Mix.Tasks.Conveyor.DiffArtifacts do
  @moduledoc """
  Compares two artifact subject descriptors.

      mix conveyor.diff_artifacts ARTIFACT_A ARTIFACT_B
  """

  use Mix.Task

  @shortdoc "Compare two artifact descriptors"

  @impl Mix.Task
  def run(args) do
    Mix.Tasks.Conveyor.EvidenceTimeMachineCommands.run_diff(
      "diff_artifacts",
      args,
      "usage: mix conveyor.diff_artifacts ARTIFACT_A ARTIFACT_B [--markdown]"
    )
  end
end
