defmodule Conveyor.ToolExecutor do
  @moduledoc """
  Sole trusted command execution path for pre-exec policy.
  """

  alias Conveyor.Factory
  alias Conveyor.Factory.Policy
  alias Conveyor.Factory.ToolInvocation
  alias Conveyor.Policy.Engine
  alias Conveyor.Policy.NormalizedCommand
  alias Conveyor.Sandbox.Runner

  @trusted_invocation_kind "tool_executor"

  defmodule Result do
    @moduledoc false

    @type t :: %__MODULE__{
            decision: Engine.Decision.t(),
            invocation: ToolInvocation.t(),
            execution: Runner.Result.t() | nil
          }

    @enforce_keys [:decision, :invocation, :execution]
    defstruct [:decision, :invocation, :execution]
  end

  @spec execute!(NormalizedCommand.t(), Policy.t(), keyword()) :: Result.t()
  def execute!(%NormalizedCommand{} = command, %Policy{} = policy, opts \\ []) do
    runner = Keyword.get(opts, :runner, &Runner.exec/1)
    decision = Engine.evaluate!(policy, command)
    started_at = DateTime.utc_now(:microsecond)

    case decision.status do
      :allowed ->
        execution = runner.(command)

        invocation =
          record_invocation!(command, policy, decision, started_at, execution, opts)

        %Result{decision: decision, invocation: invocation, execution: execution}

      :blocked ->
        invocation =
          record_invocation!(command, policy, decision, started_at, nil, opts)

        %Result{decision: decision, invocation: invocation, execution: nil}
    end
  end

  @spec trusted_invocation?(ToolInvocation.t()) :: boolean()
  def trusted_invocation?(%ToolInvocation{} = invocation) do
    invocation.invocation_kind == @trusted_invocation_kind
  end

  defp record_invocation!(command, policy, decision, started_at, execution, opts) do
    attrs =
      command
      |> base_attrs(policy, decision, started_at, opts)
      |> Map.merge(execution_attrs(execution))

    Ash.create!(ToolInvocation, attrs, domain: Factory)
  end

  defp base_attrs(command, policy, decision, started_at, opts) do
    %{
      run_attempt_id: Keyword.get(opts, :run_attempt_id),
      agent_session_id: Keyword.get(opts, :agent_session_id),
      station_run_id: Keyword.get(opts, :station_run_id),
      tool_name: command.executable,
      invocation_kind: @trusted_invocation_kind,
      command_spec: command_spec_snapshot(command, policy),
      policy_profile: Atom.to_string(policy.profile),
      cwd: command.cwd,
      env_keys: command.env_keys,
      network_mode: storage_network_mode(command.network),
      started_at: started_at,
      policy_decision: policy_decision(decision),
      status: initial_status(decision)
    }
  end

  defp execution_attrs(nil), do: %{completed_at: DateTime.utc_now(:microsecond)}

  defp execution_attrs(%Runner.Result{} = execution) do
    %{
      completed_at: DateTime.utc_now(:microsecond),
      exit_code: execution.exit_code,
      duration_ms: execution.duration_ms,
      output_sha256: output_sha256(execution),
      status: execution_status(execution.exit_code)
    }
  end

  defp initial_status(%Engine.Decision{status: :blocked}), do: :blocked
  defp initial_status(%Engine.Decision{status: :allowed}), do: :started

  defp execution_status(0), do: :succeeded
  defp execution_status(_exit_code), do: :failed

  defp policy_decision(%Engine.Decision{status: :allowed}), do: :allowed
  defp policy_decision(%Engine.Decision{status: :blocked}), do: :blocked

  defp output_sha256(%Runner.Result{} = execution) do
    :crypto.hash(:sha256, [execution.stdout, execution.stderr])
    |> Base.encode16(case: :lower)
  end

  defp command_spec_snapshot(command, policy) do
    %{
      "key" => command.executable,
      "argv" => [command.executable | command.argv],
      "cwd" => command.cwd,
      "profile" => Atom.to_string(policy.profile),
      "required" => true,
      "timeout_ms" => command.timeout_ms,
      "network" => Atom.to_string(storage_network_mode(command.network)),
      "env_allowlist" => command.env_keys,
      "output_limit_bytes" => 2_000_000,
      "repeat" => 1,
      "flake_policy" => "fail_closed",
      "infra_retry_policy" => %{"max_retries" => 0, "retry_on" => []},
      "result_format" => "stdout"
    }
  end

  defp storage_network_mode(:none), do: :none
  defp storage_network_mode(:loopback), do: :limited
  defp storage_network_mode(:egress), do: :full
end
