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

    exit_fun().(Conveyor.Doctor.exit_code(result))
  end

  defp exit_fun do
    Process.get(:conveyor_doctor_exit_fun, &System.halt/1)
  end
end
