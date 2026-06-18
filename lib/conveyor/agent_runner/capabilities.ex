defmodule Conveyor.AgentRunner.Capabilities do
  @moduledoc """
  Declared adapter capabilities used to cap autonomy explicitly.
  """

  @cancellations [:none, :best_effort, :hard]
  @diff_capture [:git_diff, :patch_file, :adapter_reported]
  @cost_reporting [:none, :estimated, :provider_reported]

  @known_limitations [
    :no_pre_exec_interception,
    :best_effort_cancellation,
    :unstructured_tool_calls,
    :adapter_reported_diff_only,
    :provider_cost_not_reported,
    :no_session_resume
  ]

  @type cancellation :: :none | :best_effort | :hard
  @type diff_capture :: :git_diff | :patch_file | :adapter_reported
  @type cost_reporting :: :none | :estimated | :provider_reported

  @type t :: %__MODULE__{
          streaming_events: boolean(),
          pre_exec_command_policy: boolean(),
          cancellation: cancellation(),
          diff_capture: diff_capture(),
          cost_reporting: cost_reporting(),
          mcp_support: boolean(),
          slash_commands_enabled: boolean(),
          structured_output: boolean(),
          session_resume: boolean(),
          known_limitations: [atom()]
        }

  defstruct streaming_events: false,
            pre_exec_command_policy: false,
            cancellation: :none,
            diff_capture: :adapter_reported,
            cost_reporting: :none,
            mcp_support: false,
            slash_commands_enabled: false,
            structured_output: false,
            session_resume: false,
            known_limitations: []

  @spec new!(t() | map() | keyword()) :: t()
  def new!(%__MODULE__{} = capabilities), do: normalize!(capabilities)

  def new!(attrs) when is_map(attrs) or is_list(attrs) do
    attrs
    |> Map.new()
    |> normalize_keys()
    |> then(&struct!(__MODULE__, &1))
    |> normalize!()
  end

  @spec autonomy_ceiling(t()) :: String.t()
  def autonomy_ceiling(%__MODULE__{pre_exec_command_policy: false}), do: "L1"

  def autonomy_ceiling(%__MODULE__{} = capabilities) do
    cond do
      l3_ready?(capabilities) ->
        "L3"

      l2_ready?(capabilities) ->
        "L2"

      true ->
        "L1"
    end
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = capabilities) do
    %{
      "streaming_events" => capabilities.streaming_events,
      "pre_exec_command_policy" => capabilities.pre_exec_command_policy,
      "cancellation" => Atom.to_string(capabilities.cancellation),
      "diff_capture" => Atom.to_string(capabilities.diff_capture),
      "cost_reporting" => Atom.to_string(capabilities.cost_reporting),
      "mcp_support" => capabilities.mcp_support,
      "slash_commands_enabled" => capabilities.slash_commands_enabled,
      "structured_output" => capabilities.structured_output,
      "session_resume" => capabilities.session_resume,
      "known_limitations" => Enum.map(capabilities.known_limitations, &Atom.to_string/1)
    }
  end

  defp l3_ready?(capabilities) do
    l2_ready?(capabilities) and capabilities.cancellation == :hard and capabilities.session_resume
  end

  defp l2_ready?(capabilities) do
    capabilities.streaming_events and capabilities.structured_output and
      capabilities.diff_capture == :git_diff
  end

  defp normalize!(%__MODULE__{} = capabilities) do
    require_boolean!(capabilities.streaming_events, :streaming_events)
    require_boolean!(capabilities.pre_exec_command_policy, :pre_exec_command_policy)
    require_boolean!(capabilities.mcp_support, :mcp_support)
    require_boolean!(capabilities.slash_commands_enabled, :slash_commands_enabled)
    require_boolean!(capabilities.structured_output, :structured_output)
    require_boolean!(capabilities.session_resume, :session_resume)
    require_enum!(capabilities.cancellation, @cancellations, :cancellation)
    require_enum!(capabilities.diff_capture, @diff_capture, :diff_capture)
    require_enum!(capabilities.cost_reporting, @cost_reporting, :cost_reporting)

    Enum.each(
      capabilities.known_limitations,
      &require_enum!(&1, @known_limitations, :known_limitations)
    )

    %{
      capabilities
      | known_limitations:
          capabilities
          |> inferred_limitations()
          |> Kernel.++(capabilities.known_limitations)
          |> Enum.uniq()
          |> Enum.sort()
    }
  end

  defp inferred_limitations(capabilities) do
    []
    |> maybe_add(not capabilities.pre_exec_command_policy, :no_pre_exec_interception)
    |> maybe_add(capabilities.cancellation == :best_effort, :best_effort_cancellation)
    |> maybe_add(not capabilities.structured_output, :unstructured_tool_calls)
    |> maybe_add(capabilities.diff_capture == :adapter_reported, :adapter_reported_diff_only)
    |> maybe_add(capabilities.cost_reporting == :none, :provider_cost_not_reported)
    |> maybe_add(not capabilities.session_resume, :no_session_resume)
  end

  defp maybe_add(limitations, true, limitation), do: [limitation | limitations]
  defp maybe_add(limitations, false, _limitation), do: limitations

  defp normalize_keys(attrs) do
    Map.new(attrs, fn
      {key, value} when is_binary(key) -> {String.to_existing_atom(key), normalize_value(value)}
      {key, value} -> {key, normalize_value(value)}
    end)
  end

  defp normalize_value(value) when is_binary(value) do
    String.to_existing_atom(value)
  rescue
    ArgumentError -> value
  end

  defp normalize_value(values) when is_list(values), do: Enum.map(values, &normalize_value/1)
  defp normalize_value(value), do: value

  defp require_boolean!(value, _field) when is_boolean(value), do: value

  defp require_boolean!(_value, field) do
    raise ArgumentError, "#{field} must be a boolean"
  end

  defp require_enum!(value, allowed, field) do
    if value in allowed do
      value
    else
      raise ArgumentError, "#{field} is invalid"
    end
  end
end
