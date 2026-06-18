defmodule Conveyor.Policy.Engine do
  @moduledoc """
  Execution policy decision service.
  """

  use Conveyor.Conductor.Child

  alias Conveyor.Factory.Policy
  alias Conveyor.Policy.NormalizedCommand

  defmodule Decision do
    @moduledoc false

    @type status :: :allowed | :blocked
    @type reason ::
            :allowed
            | :not_allowlisted
            | :denylisted
            | :env_not_allowed
            | :network_not_allowed

    @type t :: %__MODULE__{
            status: status(),
            reason: reason(),
            message: String.t(),
            policy_profile: atom(),
            command: String.t()
          }

    @enforce_keys [:status, :reason, :message, :policy_profile, :command]
    defstruct [:status, :reason, :message, :policy_profile, :command]
  end

  @spec evaluate!(Policy.t(), NormalizedCommand.t()) :: Decision.t()
  def evaluate!(%Policy{} = policy, %NormalizedCommand{} = command) do
    command_text = command_text(command)

    cond do
      not env_allowed?(policy, command) ->
        blocked(
          policy,
          command_text,
          :env_not_allowed,
          "command requests env keys outside policy"
        )

      not network_allowed?(policy, command) ->
        blocked(
          policy,
          command_text,
          :network_not_allowed,
          "command network mode is outside policy"
        )

      not allowlisted?(policy, command_text) ->
        blocked(policy, command_text, :not_allowlisted, "command is not in profile allowlist")

      denylisted?(policy, command_text) ->
        blocked(policy, command_text, :denylisted, "command matches profile denylist")

      true ->
        %Decision{
          status: :allowed,
          reason: :allowed,
          message: "command allowed by policy",
          policy_profile: policy.profile,
          command: command_text
        }
    end
  end

  defp blocked(policy, command_text, reason, message) do
    %Decision{
      status: :blocked,
      reason: reason,
      message: message,
      policy_profile: policy.profile,
      command: command_text
    }
  end

  defp env_allowed?(policy, command) do
    allowed = Map.get(policy.env_policy || %{}, "allowlist", [])

    Enum.all?(command.env_keys, &(&1 in allowed))
  end

  defp network_allowed?(policy, command) do
    case Map.get(policy.network_policy || %{}, "default", "none") do
      "none" -> command.network == :none
      "loopback" -> command.network in [:none, :loopback]
      "egress" -> command.network in [:none, :loopback, :egress]
      _other -> false
    end
  end

  defp allowlisted?(policy, command_text) do
    policy.allowlist
    |> Enum.any?(&command_matches?(command_text, &1))
  end

  defp denylisted?(policy, command_text) do
    policy.denylist
    |> Enum.any?(&command_matches?(command_text, &1))
  end

  defp command_matches?(command_text, pattern) do
    command_text == pattern or String.starts_with?(command_text, pattern <> " ")
  end

  defp command_text(command) do
    [command.executable | command.argv]
    |> Enum.join(" ")
  end
end
