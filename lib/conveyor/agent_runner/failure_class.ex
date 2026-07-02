defmodule Conveyor.AgentRunner.FailureClass do
  @moduledoc """
  Classifies an agent-call outcome as a transient INFRA failure or a WORK outcome (rt6k.6).

  INFRA = the provider/environment failed, not the agent: a timeout before completion, a
  rate limit, a 5xx/overload, a refused/reset connection, a container that failed to start.
  These are "weather" — an unattended run will hit them, and they must NOT burn an attempt.

  WORK = the agent ran and produced output, *including bad output* (nonzero exit with a diff,
  a failed assertion, garbled text). These burn an attempt.

  Fail-closed: only exact, allowlisted error signals qualify as infra; anything ambiguous
  defaults to `:work` so an agent that crashes itself can never earn infinite retries.
  """

  @type outcome :: %{required(:exit_code) => integer(), optional(:output) => String.t()}
  @type class ::
          :timeout
          | :rate_limited
          | :provider_unavailable
          | :connection_failed
          | :container_start_failed

  # Watchdog timeout exit code (AdapterBase): our own signal, unambiguous.
  @timeout_exit_code 124

  @rate_limited ~r/\b429\b|rate limit|too many requests/i
  @provider_unavailable ~r/\b(500|502|503|504|529)\b|overloaded|service unavailable/i
  @connection_failed ~r/connection (refused|reset)|econnrefused/i
  @container_start_failed ~r/container failed to start|failed to create container/i

  @spec classify(outcome()) :: {:infra, class()} | :work
  def classify(%{exit_code: 0}), do: :work
  def classify(%{exit_code: @timeout_exit_code}), do: {:infra, :timeout}

  def classify(%{exit_code: _} = outcome) do
    output = Map.get(outcome, :output, "") || ""

    cond do
      matches?(output, @rate_limited) -> {:infra, :rate_limited}
      matches?(output, @provider_unavailable) -> {:infra, :provider_unavailable}
      matches?(output, @connection_failed) -> {:infra, :connection_failed}
      matches?(output, @container_start_failed) -> {:infra, :container_start_failed}
      true -> :work
    end
  end

  @doc "True when the outcome is a transient infra failure (does not burn an attempt)."
  @spec infra?(outcome()) :: boolean()
  def infra?(outcome), do: match?({:infra, _}, classify(outcome))

  defp matches?(output, regex), do: Regex.match?(regex, output)
end
