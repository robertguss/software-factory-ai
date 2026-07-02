defmodule Conveyor.Recovery.FailureFingerprint do
  @moduledoc """
  Stable digest of *why* an attempt failed (rt6k.3), used by the convergence sentinel to detect
  the same failure recurring across retries.

  The fingerprint is computed from the identity of the failure only — gate status plus each
  finding's `category`, `code`, `path`, `acceptance_criterion_id`, `stage`, and `test_id` — and
  is deliberately blind to noise (human messages, severities, durations, timestamps, tmp paths).
  Two attempts that fail the same way produce the same digest across runs; a different failing
  criterion or test produces a different digest.
  """

  alias Conveyor.Gate

  # Only stable identity keys; message/severity/duration/timestamps are intentionally excluded.
  @identity_keys ~w(category code path acceptance_criterion_id stage test_id)

  @spec compute(Gate.Result.t()) :: String.t()
  def compute(%Gate.Result{status: status, findings: findings}),
    do: compute(status, findings)

  @spec compute(atom() | String.t(), [map()]) :: String.t()
  def compute(status, findings) when is_list(findings) do
    normalized = %{
      "status" => to_string(status),
      "findings" => findings |> Enum.map(&identity/1) |> Enum.sort()
    }

    hash = :crypto.hash(:sha256, Jason.encode!(normalized))
    "sha256:" <> Base.encode16(hash, case: :lower)
  end

  # How many findings a failure carries — used by callers to spot regression (more failures than
  # the prior attempt) when budget exhausts.
  @spec finding_count(Gate.Result.t()) :: non_neg_integer()
  def finding_count(%Gate.Result{findings: findings}), do: length(findings)

  defp identity(finding) when is_map(finding) do
    Enum.map(@identity_keys, fn key -> Map.get(finding, key) end)
  end
end
