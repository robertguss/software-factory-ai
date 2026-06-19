defmodule Conveyor.Planning.ContextAssemblyManifest do
  @moduledoc """
  Deterministic context assembly with explicit shed reasons.

  Critical content being shed fails before any provider call. Noncritical shed
  content is recorded for auditability.
  """

  defstruct [
    :status,
    :provider_call_allowed?,
    :token_budget,
    :estimator_version,
    :tokenizer,
    :ordered_refs,
    :included_refs,
    :shed_reasons
  ]

  @priority_order %{critical: 0, required: 1, supporting: 2, advisory: 3}

  @spec assemble([map()], keyword()) :: %__MODULE__{}
  def assemble(items, opts) when is_list(items) and is_list(opts) do
    token_budget = Keyword.fetch!(opts, :token_budget)
    tokenizer = tokenizer(opts)
    estimator_version = tokenizer.version

    {included, shed} =
      items
      |> Enum.map(&normalize_item/1)
      |> Enum.sort_by(&{Map.fetch!(@priority_order, &1.priority), &1.ref})
      |> Enum.reduce({[], []}, fn item, {included, shed} ->
        used = Enum.sum(Enum.map(included, & &1.estimated_tokens))

        if used + item.estimated_tokens <= token_budget do
          {[item | included], shed}
        else
          {included, [shed_reason(item) | shed]}
        end
      end)

    critical_shed? = Enum.any?(shed, &(&1.reason == :critical_content_shed))
    ordered_refs = included |> Enum.reverse() |> Enum.map(& &1.ref)

    %__MODULE__{
      status: if(critical_shed?, do: :failed_pre_provider, else: :ready),
      provider_call_allowed?: not critical_shed?,
      token_budget: token_budget,
      estimator_version: estimator_version,
      tokenizer: tokenizer,
      ordered_refs: ordered_refs,
      included_refs: Enum.sort(ordered_refs),
      shed_reasons: Enum.sort_by(shed, & &1.ref)
    }
  end

  defp normalize_item(item) do
    %{
      ref: item |> value(:ref) |> to_string(),
      priority: value(item, :priority),
      content_kind: value(item, :content_kind),
      estimated_tokens: value(item, :estimated_tokens) || 0
    }
  end

  defp shed_reason(%{priority: :critical} = item),
    do:
      item
      |> base_shed_reason(:critical_content_shed)
      |> maybe_put_content_kind(item.content_kind)

  defp shed_reason(item),
    do:
      item
      |> base_shed_reason(:budget_exceeded)
      |> maybe_put_content_kind(item.content_kind)

  defp base_shed_reason(item, reason) do
    %{
      ref: item.ref,
      reason: reason,
      priority: item.priority
    }
  end

  defp maybe_put_content_kind(reason, nil), do: reason

  defp maybe_put_content_kind(reason, content_kind),
    do: Map.put(reason, :content_kind, content_kind)

  defp tokenizer(opts) do
    case Keyword.get(opts, :tokenizer) do
      %{adapter: adapter, version: version} -> %{adapter: adapter, version: version}
      %{"adapter" => adapter, "version" => version} -> %{adapter: adapter, version: version}
      nil -> %{adapter: "fallback", version: Keyword.fetch!(opts, :estimator_version)}
    end
  end

  defp value(map, key), do: Map.get(map, key) || Map.get(map, to_string(key))
end
