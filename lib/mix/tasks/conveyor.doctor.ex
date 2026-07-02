defmodule Mix.Tasks.Conveyor.Doctor do
  @moduledoc """
  Runs Conveyor prerequisite checks.

      mix conveyor.doctor
      mix conveyor.doctor SAMPLE_PROJECT_PATH
      mix conveyor.doctor --adapter codex

  `--adapter` selects which agent backend's prereqs to validate (default: the configured backend,
  `claude_code`). Codex prereqs are checked only when codex is the selected backend.
  """

  use Mix.Task

  @shortdoc "Check Conveyor project prerequisites"

  @impl Mix.Task
  def run(args) do
    {opts, positional, _} = OptionParser.parse(args, strict: [adapter: :string])
    project_path = List.first(positional) || File.cwd!()
    result = Conveyor.Doctor.run(project_path, adapter: Keyword.get(opts, :adapter))
    Mix.shell().info(Conveyor.Doctor.format(result))

    exit_fun().(Conveyor.Doctor.exit_code(result))
  end

  defp exit_fun do
    Process.get(:conveyor_doctor_exit_fun, &System.halt/1)
  end
end
