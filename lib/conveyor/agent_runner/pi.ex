defmodule Conveyor.AgentRunner.Pi do
  @moduledoc """
  Pi adapter for the `Conveyor.AgentRunner` behaviour.

  The default runtime path opens Pi's JSONL RPC mode through a BEAM Port. Tests
  and deterministic demos can inject an `:rpc_client` function with the same
  event callback contract, so the core adapter logic is exercised without live
  provider calls.
  """

  @behaviour Conveyor.AgentRunner

  alias Conveyor.AgentRunner.Capabilities
  alias Conveyor.AgentRunner.EventRecorder
  alias Conveyor.AgentRunner.RawRunResult
  alias Conveyor.AgentRunner.SessionLimits
  alias Conveyor.Artifacts.BlobStore
  alias Conveyor.Factory
  alias Conveyor.Factory.AgentSession
  alias Conveyor.Factory.Policy
  alias Conveyor.Factory.RunPrompt
  alias Conveyor.Policy.RunBudgetGuard

  @adapter "pi"
  @host_controlled_tools :pi_host_controlled_tools
  @observe_only :pi_in_container_observe_only
  @profiles [@host_controlled_tools, @observe_only]

  @type profile :: :pi_host_controlled_tools | :pi_in_container_observe_only
  @type rpc_request :: %{
          required(:adapter) => String.t(),
          required(:profile) => String.t(),
          required(:session_id) => String.t(),
          required(:prompt) => String.t(),
          required(:workspace_path) => String.t(),
          required(:policy) => map(),
          required(:container) => map(),
          required(:environment) => map()
        }
  @type rpc_event :: map()
  @type rpc_client :: (rpc_request(), (rpc_event() -> any()) -> {:ok, map()} | {:error, term()})

  @impl true
  def capabilities, do: capabilities(@host_controlled_tools)

  @spec capabilities(profile() | String.t()) :: Capabilities.t()
  def capabilities(profile) do
    profile
    |> normalize_profile!()
    |> capabilities_for_profile()
  end

  @spec profiles() :: [profile()]
  def profiles, do: @profiles

  @impl true
  def run(%RunPrompt{} = run_prompt, workspace, %Policy{} = policy, opts \\ []) do
    profile = opts |> Keyword.get(:profile, @host_controlled_tools) |> normalize_profile!()
    workspace_path = workspace_path!(workspace)
    base_commit = base_commit!(workspace, opts)
    session_id = Keyword.get(opts, :session_id, "pi-#{Ash.UUID.generate()}")
    agent_session_id = Keyword.fetch!(opts, :agent_session_id)
    blob_opts = Keyword.take(opts, [:blob_root])

    limits = SessionLimits.new(session_limit_opts(opts))
    recorder = event_recorder(agent_session_id, session_id, blob_opts, limits)
    request = request(run_prompt, workspace_path, policy, profile, session_id, opts)
    rpc_client = Keyword.get(opts, :rpc_client, &run_port_rpc/2)

    try do
      with {:ok, rpc_result} <- rpc_client.(request, recorder) do
        final_sequence = record_terminal_events!(recorder, rpc_result)
        raw_transcript_ref = raw_transcript_ref(rpc_result, blob_opts)
        diff_ref = capture_diff!(workspace_path, base_commit, blob_opts)
        result = raw_run_result(rpc_result, diff_ref, raw_transcript_ref, profile, final_sequence)

        update_agent_session!(agent_session_id, session_id, result, raw_transcript_ref)

        {:ok, result}
      end
    catch
      {:agent_session_stopped, finding, measurements} ->
        record_budget_exhaustion(opts, finding, measurements)
        update_agent_session_failed!(agent_session_id, session_id, finding)

        cancel(session_id,
          agent_session_id: agent_session_id,
          blob_root: Keyword.get(opts, :blob_root),
          profile: profile,
          reason: finding["exceeded_cap"],
          canceller: Keyword.get(opts, :canceller, fn _session_id -> :ok end)
        )

        {:error, finding}
    end
  end

  @impl true
  def cancel(session_id), do: cancel(session_id, [])

  @spec cancel(String.t(), keyword()) :: :ok | {:error, term()}
  def cancel(session_id, opts) when is_binary(session_id) and session_id != "" do
    agent_session_id = Keyword.get(opts, :agent_session_id)
    blob_opts = Keyword.take(opts, [:blob_root])
    reason = Keyword.get(opts, :reason, "operator_requested")
    profile = opts |> Keyword.get(:profile, @host_controlled_tools) |> normalize_profile!()
    cancellation = capabilities(profile).cancellation

    if agent_session_id do
      record_cancel_events!(agent_session_id, session_id, reason, cancellation, blob_opts)
    end

    opts
    |> Keyword.get(:canceller, &default_cancel/1)
    |> then(& &1.(session_id))
  end

  @spec run_port_rpc(rpc_request(), (rpc_event() -> any())) :: {:ok, map()} | {:error, term()}
  def run_port_rpc(request, emit_event) when is_function(emit_event, 1) do
    command = Map.get(request, :command, ["pi", "rpc", "--jsonl"])
    timeout_ms = Map.get(request, :timeout_ms, 120_000)
    workspace_path = Map.fetch!(request, :workspace_path)

    with {:ok, executable, argv} <- split_command(command),
         true <- File.exists?(executable) or {:error, {:executable_not_found, executable}} do
      port =
        Port.open({:spawn_executable, executable}, [
          :binary,
          :exit_status,
          {:args, argv},
          {:cd, workspace_path}
        ])

      Port.command(port, Jason.encode!(request) <> "\n")
      collect_port(port, emit_event, "", timeout_ms)
    end
  end

  defp capabilities_for_profile(@host_controlled_tools) do
    Capabilities.new!(%{
      streaming_events: true,
      pre_exec_command_policy: true,
      cancellation: :best_effort,
      diff_capture: :git_diff,
      cost_reporting: :estimated,
      mcp_support: false,
      slash_commands_enabled: false,
      structured_output: true,
      session_resume: false,
      known_limitations: [:best_effort_cancellation]
    })
  end

  defp capabilities_for_profile(@observe_only) do
    Capabilities.new!(%{
      streaming_events: true,
      pre_exec_command_policy: false,
      cancellation: :best_effort,
      diff_capture: :git_diff,
      cost_reporting: :estimated,
      mcp_support: false,
      slash_commands_enabled: false,
      structured_output: true,
      session_resume: false,
      known_limitations: [:best_effort_cancellation]
    })
  end

  defp request(run_prompt, workspace_path, policy, profile, session_id, opts) do
    %{
      adapter: @adapter,
      profile: Atom.to_string(profile),
      session_id: session_id,
      prompt: run_prompt.body,
      workspace_path: workspace_path,
      policy: policy_snapshot(policy),
      container: %{
        image: Keyword.get(opts, :container_image_ref),
        mount_mode: Keyword.get(opts, :mount_mode, :read_write)
      },
      environment: %{
        env_keys: Keyword.get(opts, :env_keys, []),
        cache_mounts: Keyword.get(opts, :cache_mounts, [])
      },
      timeout_ms: Keyword.get(opts, :timeout_ms, 120_000),
      command: Keyword.get(opts, :pi_command, ["pi", "rpc", "--jsonl"])
    }
  end

  defp policy_snapshot(policy) do
    %{
      id: policy.id,
      name: policy.name,
      profile: Atom.to_string(policy.profile),
      allowlist: policy.allowlist,
      denylist: policy.denylist,
      env_policy: policy.env_policy,
      network_policy: policy.network_policy,
      budget_policy: policy.budget_policy,
      autonomy_ceiling: policy.autonomy_ceiling
    }
  end

  defp event_recorder(agent_session_id, session_id, blob_opts, limits) do
    sequence = :counters.new(1, [])
    :counters.add(sequence, 1, EventRecorder.next_sequence_no(agent_session_id) - 1)
    limits_key = {__MODULE__, make_ref()}
    Process.put(limits_key, limits)

    fn event ->
      limit_state = Process.get(limits_key)

      case SessionLimits.observe(limit_state, event) do
        {:ok, next_limits} ->
          Process.put(limits_key, next_limits)

        {:halt, finding, measurements} ->
          throw({:agent_session_stopped, finding, measurements})
      end

      :counters.add(sequence, 1, 1)
      sequence_no = :counters.get(sequence, 1)

      event
      |> normalize_event(sequence_no, agent_session_id, session_id)
      |> EventRecorder.record!(blob_opts)

      sequence_no
    end
  end

  defp session_limit_opts(opts) do
    Keyword.take(opts, [:max_wall_clock_ms, :max_idle_ms, :max_output_bytes, :now_ms])
  end

  defp normalize_event(event, sequence_no, agent_session_id, session_id) do
    event = normalize_keys(event)
    event_type = Map.get(event, :event_type) || Map.get(event, :type)

    %{
      agent_session_id: agent_session_id,
      adapter: @adapter,
      session_id: Map.get(event, :session_id, session_id),
      sequence_no: Map.get(event, :sequence_no, sequence_no),
      event_type: event_type,
      payload: Map.get(event, :payload, event_payload(event)),
      raw: event,
      occurred_at: Map.get(event, :occurred_at, DateTime.utc_now(:microsecond))
    }
  end

  defp event_payload(event) do
    Map.drop(event, [:event_type, :type, :sequence_no, :session_id, :raw, :occurred_at])
  end

  defp record_terminal_events!(recorder, rpc_result) do
    sequence_no =
      recorder.(%{
        type: "final_response",
        payload: %{
          "summary" => Map.get(rpc_result, "summary") || Map.get(rpc_result, :summary, "")
        },
        raw: Map.get(rpc_result, "final_response") || Map.get(rpc_result, :final_response)
      })

    recorder.(%{
      type: "session_completed",
      payload: %{
        "status" => Map.get(rpc_result, "status") || Map.get(rpc_result, :status, "succeeded")
      }
    })

    sequence_no + 1
  end

  defp raw_run_result(rpc_result, diff_ref, raw_transcript_ref, profile, final_sequence) do
    %RawRunResult{
      summary: Map.get(rpc_result, "summary") || Map.get(rpc_result, :summary, ""),
      messages: Map.get(rpc_result, "messages") || Map.get(rpc_result, :messages, []),
      tool_calls: Map.get(rpc_result, "tool_calls") || Map.get(rpc_result, :tool_calls, []),
      attempted_commands:
        Map.get(rpc_result, "attempted_commands") || Map.get(rpc_result, :attempted_commands, []),
      diff_ref: diff_ref,
      metadata: %{
        "adapter" => @adapter,
        "profile" => Atom.to_string(profile),
        "session_id" => Map.get(rpc_result, "session_id") || Map.get(rpc_result, :session_id),
        "raw_transcript_ref" => raw_transcript_ref,
        "final_sequence_no" => final_sequence
      }
    }
  end

  defp raw_transcript_ref(rpc_result, blob_opts) do
    rpc_result
    |> Jason.encode!(pretty: true)
    |> BlobStore.write!(blob_opts)
    |> Map.fetch!(:ref)
  end

  defp capture_diff!(workspace_path, base_commit, blob_opts) do
    {diff, 0} =
      System.cmd("git", ["-C", workspace_path, "diff", "--binary", base_commit, "--"],
        stderr_to_stdout: true
      )

    diff
    |> BlobStore.write!(blob_opts)
    |> Map.fetch!(:ref)
  end

  defp update_agent_session!(agent_session_id, session_id, result, raw_transcript_ref) do
    AgentSession
    |> Ash.read!(domain: Factory)
    |> Enum.find(&(&1.id == agent_session_id))
    |> case do
      nil ->
        :ok

      session ->
        Ash.update!(
          session,
          %{
            adapter_session_id: result.metadata["session_id"] || session_id,
            status: :succeeded,
            completed_at: DateTime.utc_now(:microsecond),
            raw_result_ref: raw_transcript_ref
          },
          domain: Factory
        )
    end
  end

  defp update_agent_session_failed!(agent_session_id, session_id, finding) do
    AgentSession
    |> Ash.read!(domain: Factory)
    |> Enum.find(&(&1.id == agent_session_id))
    |> case do
      nil ->
        :ok

      session ->
        Ash.update!(
          session,
          %{
            adapter_session_id: session.adapter_session_id || session_id,
            status: :failed,
            completed_at: DateTime.utc_now(:microsecond),
            raw_result_ref: finding["exceeded_cap"]
          },
          domain: Factory
        )
    end
  end

  defp record_budget_exhaustion(opts, finding, measurements) do
    case Keyword.get(opts, :run_budget_id) do
      nil ->
        :ok

      run_budget_id ->
        RunBudgetGuard.record!(
          run_budget_id,
          Map.put(measurements, :reason, finding["message"]),
          Keyword.take(opts, [:run_attempt_id, :slice_id, :project_id])
        )
    end
  end

  defp record_cancel_events!(agent_session_id, session_id, reason, cancellation, blob_opts) do
    first_sequence = EventRecorder.next_sequence_no(agent_session_id)

    EventRecorder.record!(
      %{
        agent_session_id: agent_session_id,
        adapter: @adapter,
        session_id: session_id,
        sequence_no: first_sequence,
        event_type: "cancel_requested",
        payload: %{
          "reason" => reason,
          "cancellation" => Atom.to_string(cancellation)
        },
        raw: %{"reason" => reason, "cancellation" => Atom.to_string(cancellation)}
      },
      blob_opts
    )

    EventRecorder.record!(
      %{
        agent_session_id: agent_session_id,
        adapter: @adapter,
        session_id: session_id,
        sequence_no: first_sequence + 1,
        event_type: "cancel_acknowledged",
        payload: %{
          "reason" => reason,
          "cancellation" => Atom.to_string(cancellation)
        },
        raw: %{"acknowledged" => true}
      },
      blob_opts
    )
  end

  defp default_cancel(_session_id) do
    case System.find_executable("pi") do
      nil -> {:error, :pi_executable_not_found}
      _path -> :ok
    end
  end

  defp workspace_path!(workspace) do
    workspace
    |> field(:path, :workspace_path)
    |> require_non_empty_string!(:workspace_path)
    |> Path.expand()
  end

  defp base_commit!(workspace, opts) do
    opts
    |> Keyword.get(:base_commit)
    |> Kernel.||(field(workspace, :base_commit))
    |> require_non_empty_string!(:base_commit)
  end

  defp field(map, key) when is_map(map),
    do: Map.get(map, key) || Map.get(map, Atom.to_string(key))

  defp field(struct, primary, fallback) do
    field(struct, primary) || field(struct, fallback)
  end

  defp require_non_empty_string!(value, _field) when is_binary(value) and value != "", do: value

  defp require_non_empty_string!(_value, field) do
    raise ArgumentError, "#{field} must be a non-empty string"
  end

  defp normalize_profile!(profile) when profile in @profiles, do: profile

  defp normalize_profile!(profile) when is_binary(profile) do
    Enum.find(@profiles, &(Atom.to_string(&1) == profile)) ||
      raise ArgumentError, "unknown Pi profile #{inspect(profile)}"
  end

  defp normalize_profile!(profile),
    do: raise(ArgumentError, "unknown Pi profile #{inspect(profile)}")

  defp normalize_keys(map) when is_map(map) do
    Map.new(map, fn
      {key, value} when is_binary(key) -> {String.to_existing_atom(key), value}
      pair -> pair
    end)
  end

  defp split_command([executable | argv]) when is_binary(executable) do
    executable =
      if Path.type(executable) == :absolute do
        executable
      else
        System.find_executable(executable) || executable
      end

    {:ok, executable, argv}
  end

  defp split_command(_command), do: {:error, :invalid_pi_command}

  defp collect_port(port, emit_event, buffer, timeout_ms) do
    receive do
      {^port, {:data, data}} ->
        {lines, buffer} = complete_lines(buffer <> data)
        result = Enum.reduce_while(lines, nil, &handle_port_line(&1, emit_event, &2))

        case result do
          nil -> collect_port(port, emit_event, buffer, timeout_ms)
          {:ok, rpc_result} -> {:ok, rpc_result}
          {:error, reason} -> {:error, reason}
        end

      {^port, {:exit_status, 0}} ->
        {:ok,
         %{"summary" => "", "messages" => [], "tool_calls" => [], "attempted_commands" => []}}

      {^port, {:exit_status, status}} ->
        {:error, {:pi_exited, status}}
    after
      timeout_ms ->
        Port.close(port)
        {:error, :timeout}
    end
  end

  defp complete_lines(buffer) do
    parts = String.split(buffer, "\n")
    {Enum.drop(parts, -1), List.last(parts) || ""}
  end

  defp handle_port_line("", _emit_event, result), do: {:cont, result}

  defp handle_port_line(line, emit_event, _result) do
    case Jason.decode(line) do
      {:ok, %{"event_type" => _} = event} ->
        emit_event.(event)
        {:cont, nil}

      {:ok, %{"type" => "event", "event" => event}} ->
        emit_event.(event)
        {:cont, nil}

      {:ok, %{"type" => "result", "result" => result}} ->
        {:halt, {:ok, result}}

      {:ok, %{"type" => "error", "error" => reason}} ->
        {:halt, {:error, reason}}

      {:ok, result} when is_map(result) ->
        {:halt, {:ok, result}}

      {:error, reason} ->
        {:halt, {:error, {:invalid_jsonl, reason}}}
    end
  end
end
