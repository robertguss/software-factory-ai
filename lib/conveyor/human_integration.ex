defmodule Conveyor.HumanIntegration do
  @moduledoc """
  Records the Phase-1 human integration decision for a run attempt.
  """

  alias Conveyor.Factory
  alias Conveyor.Factory.Epic
  alias Conveyor.Factory.HumanApproval
  alias Conveyor.Factory.Plan
  alias Conveyor.Factory.RunAttempt
  alias Conveyor.Factory.Slice

  @spec record!(keyword() | map()) :: HumanApproval.t()
  def record!(attrs) do
    attrs = Map.new(attrs)
    run_attempt = run_attempt!(Map.fetch!(attrs, :run_attempt_id))
    slice = slice!(run_attempt.slice_id)
    project_id = project_id!(slice)
    external_commit = attrs[:external_commit] |> normalize_blank()
    not_integrated? = truthy?(attrs[:not_integrated])

    cond do
      external_commit && not_integrated? ->
        raise ArgumentError, "provide either external commit or not_integrated, not both"

      external_commit ->
        create_approval!(attrs, run_attempt, slice, project_id, %{
          decision: :recorded_external_action,
          external_commit: external_commit,
          equivalence_decision: :unknown
        })

      not_integrated? ->
        create_approval!(attrs, run_attempt, slice, project_id, %{
          decision: :not_integrated,
          external_commit: nil,
          equivalence_decision: nil
        })

      true ->
        raise ArgumentError,
              "human integration requires an external commit or not_integrated decision"
    end
  end

  defp create_approval!(attrs, run_attempt, slice, project_id, decision_attrs) do
    HumanApproval
    |> Ash.create!(
      Map.merge(
        %{
          project_id: project_id,
          slice_id: slice.id,
          run_attempt_id: run_attempt.id,
          approval_type: "external_integration",
          actor: Map.get(attrs, :actor, "human"),
          rationale: attrs[:rationale],
          artifact_sha256_refs: Map.get(attrs, :artifact_sha256_refs, [])
        },
        decision_attrs
      ),
      domain: Factory
    )
  end

  defp run_attempt!(id) do
    RunAttempt
    |> Ash.read!(domain: Factory)
    |> Enum.find(&(&1.id == id))
    |> case do
      nil -> raise ArgumentError, "unknown run_attempt_id #{inspect(id)}"
      run_attempt -> run_attempt
    end
  end

  defp slice!(id) do
    Slice
    |> Ash.read!(domain: Factory)
    |> Enum.find(&(&1.id == id))
    |> case do
      nil -> raise ArgumentError, "unknown slice_id #{inspect(id)}"
      slice -> slice
    end
  end

  defp project_id!(slice) do
    epic =
      Epic
      |> Ash.read!(domain: Factory)
      |> Enum.find(&(&1.id == slice.epic_id))

    plan =
      Plan
      |> Ash.read!(domain: Factory)
      |> Enum.find(&(&1.id == epic.plan_id))

    plan.project_id
  end

  defp normalize_blank(nil), do: nil

  defp normalize_blank(value) when is_binary(value),
    do: if(String.trim(value) == "", do: nil, else: value)

  defp normalize_blank(value), do: value

  defp truthy?(value), do: value in [true, "true", "on", "1", 1]
end
