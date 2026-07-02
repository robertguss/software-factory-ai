defmodule Conveyor.Recovery.ConvergenceSentinel do
  @moduledoc """
  Anti-thrash decision for the attempt loop (rt6k.3): stop early instead of burning the whole
  attempt budget on a slice that is not converging.

  Two signals, checked cheapest-first:

    * **`no_progress`** — the attempt changed nothing (empty diff). Retrying the same prompt is
      pure thrash; park immediately (no prior attempt needed).
    * **`convergence_stall`** — this attempt produced the *same* failure fingerprint as the
      previous one. The retry reproduced the identical failure, so more attempts are near-certain
      waste; park.

  Park reasons are typed strings that fold into the park-reason taxonomy (a3hf.1.3.1).
  """

  @no_progress "no_progress"
  @convergence_stall "convergence_stall"

  @type decision :: {:park, String.t()} | :continue

  @spec decide(%{
          optional(:diff_empty?) => boolean(),
          optional(:prev_fingerprint) => String.t() | nil,
          optional(:current_fingerprint) => String.t() | nil
        }) :: decision()
  def decide(%{diff_empty?: true}), do: {:park, @no_progress}

  def decide(%{prev_fingerprint: fingerprint, current_fingerprint: fingerprint})
      when is_binary(fingerprint),
      do: {:park, @convergence_stall}

  def decide(_signals), do: :continue

  @spec no_progress() :: String.t()
  def no_progress, do: @no_progress

  @spec convergence_stall() :: String.t()
  def convergence_stall, do: @convergence_stall
end
