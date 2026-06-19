defmodule Conveyor.Planning.Scout do
  @moduledoc """
  Optional read-only planning scout for unresolved synthesis.

  The scout reports what it examined under hard context budgets. It cannot
  create impact or authority.
  """

  defmodule Result do
    @moduledoc "Planning scout run report."

    @enforce_keys [:status, :read_only?, :authority_effect, :examined_sources, :budgets]
    defstruct [
      :status,
      :reason,
      :read_only?,
      :authority_effect,
      :examined_sources,
      :budgets,
      :extractor_failures,
      :invented_impact?
    ]
  end

  @spec run(map()) :: Result.t()
  def run(%{unresolved_synthesis?: false}) do
    %Result{
      status: :not_run,
      reason: :synthesis_already_resolved,
      read_only?: true,
      authority_effect: :none,
      examined_sources: [],
      budgets: %{},
      extractor_failures: [],
      invented_impact?: false
    }
  end

  def run(%{unresolved_synthesis?: true} = attrs) do
    budgets = %{
      context_budget_cents: Map.fetch!(attrs, :context_budget_cents),
      context_wall_clock_ms: Map.fetch!(attrs, :context_wall_clock_ms)
    }

    if budget_exceeded?(attrs, budgets) do
      %Result{
        status: :budget_exceeded,
        read_only?: true,
        authority_effect: :none,
        examined_sources: [],
        budgets: budgets,
        extractor_failures: [],
        invented_impact?: false
      }
    else
      run_within_budget(attrs, budgets)
    end
  end

  defp run_within_budget(attrs, budgets) do
    sources =
      attrs
      |> Map.get(:sources, [])
      |> Enum.map(&source_entry/1)
      |> Enum.sort_by(& &1.ref)

    extractor_failures =
      attrs
      |> Map.get(:extractor_failures, [])
      |> Enum.map(&extractor_failure/1)
      |> Enum.sort_by(& &1.key)

    %Result{
      status: if(extractor_failures == [], do: :complete, else: :partial),
      read_only?: true,
      authority_effect: :none,
      examined_sources: sources,
      budgets: budgets,
      extractor_failures: extractor_failures,
      invented_impact?: false
    }
  end

  defp source_entry(source) do
    %{
      ref: source |> value(:ref) |> to_string(),
      bytes: value(source, :bytes) || 0
    }
  end

  defp extractor_failure(failure) do
    %{
      key: failure |> value(:key) |> to_string(),
      reason: value(failure, :reason)
    }
  end

  defp budget_exceeded?(attrs, budgets) do
    exceeds?(value(attrs, :estimated_context_cents), budgets.context_budget_cents) or
      exceeds?(value(attrs, :estimated_wall_clock_ms), budgets.context_wall_clock_ms)
  end

  defp exceeds?(estimate, limit) when is_number(estimate), do: estimate > limit
  defp exceeds?(_estimate, _limit), do: false

  defp value(map, key), do: Map.get(map, key) || Map.get(map, to_string(key))
end
