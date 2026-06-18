defmodule Conveyor.Sandbox.PolicyExecutor do
  @moduledoc """
  Runs policy-checked commands inside a materialized sandbox.
  """

  alias Conveyor.Factory.Policy
  alias Conveyor.Policy.NormalizedCommand
  alias Conveyor.Sandbox.DockerRunner
  alias Conveyor.Sandbox.Materialized
  alias Conveyor.ToolExecutor

  @spec execute!(Materialized.t(), NormalizedCommand.t(), Policy.t(), keyword()) ::
          ToolExecutor.Result.t()
  def execute!(
        %Materialized{} = materialized,
        %NormalizedCommand{} = command,
        %Policy{} = policy,
        opts \\ []
      ) do
    docker_opts = Keyword.get(opts, :docker_opts, [])

    ToolExecutor.execute!(
      command,
      policy,
      Keyword.put(opts, :runner, fn allowed_command ->
        DockerRunner.exec(materialized, allowed_command, docker_opts)
      end)
    )
  end
end
