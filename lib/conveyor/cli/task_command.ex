defmodule Conveyor.CLI.TaskCommand do
  @moduledoc """
  Shared output/exit/error helpers for the `conveyor.task.*` authoring CLI (KTD4).

  Keeps each verb a thin wrapper over `Conveyor.TaskGraph`: pure-JSON on stdout, human diagnostics
  on stderr, and exit through a single test-overridable seam (`:conveyor_task_exit_fun`, defaulting
  to `System.halt/1`).
  """

  alias Conveyor.CLI.ExitCodes

  @seam :conveyor_task_exit_fun

  @doc "Run `fun`, mapping an `ArgumentError` to a clean non-zero exit with the message on stderr."
  def guard(fun) do
    fun.()
  rescue
    error in [ArgumentError] -> fail!(Exception.message(error))
  end

  @doc "Emit `data` as JSON on stdout and exit success."
  def emit!(data) do
    data |> Jason.encode!() |> Mix.shell().info()
    halt(:success)
  end

  @doc "Print `message` on stderr and exit with `code` (default: plan/readiness blocked)."
  def fail!(message, code \\ :plan_or_readiness_blocked) do
    IO.puts(:stderr, message)
    halt(code)
  end

  @doc "Split a comma-separated option value into a trimmed list (nil/blank -> [])."
  def csv(nil), do: []
  def csv(""), do: []
  def csv(value), do: value |> String.split(",", trim: true) |> Enum.map(&String.trim/1)

  defp halt(code), do: exit_fun().(ExitCodes.fetch!(code))

  defp exit_fun, do: Process.get(@seam, &System.halt/1)
end
