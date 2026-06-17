defmodule Mix.Tasks.Conveyor.Doctor do
  @moduledoc """
  Runs Conveyor prerequisite checks.

      mix conveyor.doctor
      mix conveyor.doctor SAMPLE_PROJECT_PATH
  """

  use Mix.Task

  @shortdoc "Check Conveyor project prerequisites"

  @impl Mix.Task
  def run(args) do
    project_path = List.first(args) || File.cwd!()
    result = Conveyor.Doctor.run(project_path)
    Mix.shell().info(Conveyor.Doctor.format(result))

    if result.status == :failed do
      Mix.raise("conveyor.doctor failed")
    end
  end
end
