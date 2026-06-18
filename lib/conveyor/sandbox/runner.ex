defmodule Conveyor.Sandbox.Runner do
  @moduledoc """
  Sandbox runner behaviour and minimal host command runner used behind ToolExecutor.

  The policy boundary lives in `Conveyor.ToolExecutor`; this module only runs a
  command that has already been normalized and allowed.
  """

  alias Conveyor.Factory.RunSpec
  alias Conveyor.Policy.NormalizedCommand
  alias Conveyor.Sandbox.Materialized

  defmodule Result do
    @moduledoc false

    @type t :: %__MODULE__{
            exit_code: non_neg_integer(),
            stdout: String.t(),
            stderr: String.t(),
            duration_ms: non_neg_integer()
          }

    @enforce_keys [:exit_code, :stdout, :stderr, :duration_ms]
    defstruct [:exit_code, :stdout, :stderr, :duration_ms]
  end

  @callback materialize(RunSpec.t(), keyword()) :: {:ok, Materialized.t()} | {:error, term()}
  @callback exec(Materialized.t(), NormalizedCommand.t(), keyword()) ::
              Result.t() | {:ok, Result.t()} | {:error, term()}
  @callback destroy(Materialized.t(), keyword()) :: :ok | {:error, term()}

  @spec exec(NormalizedCommand.t()) :: Result.t()
  def exec(%NormalizedCommand{} = command) do
    started = System.monotonic_time(:millisecond)

    {stdout, exit_code} =
      System.cmd(command.executable, command.argv,
        cd: command.cwd,
        env: command_env(command.env_keys),
        stderr_to_stdout: true
      )

    %Result{
      exit_code: exit_code,
      stdout: stdout,
      stderr: "",
      duration_ms: max(System.monotonic_time(:millisecond) - started, 0)
    }
  end

  defp command_env(env_keys) do
    Enum.map(env_keys, fn key -> {key, System.get_env(key) || ""} end)
  end
end
