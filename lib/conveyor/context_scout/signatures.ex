defmodule Conveyor.ContextScout.Signatures do
  @moduledoc """
  Language-neutral, regex-based interface signature extraction (aabq.2).

  Given a file's content and path, returns the interface-bearing lines (module heads, public
  function/class/type signatures, exports) in source order, bounded. This is the interface anchor
  the scout injects for a slice — a consumer slice should see the producer slice's actual exported
  signatures, since cross-slice interface drift is what kills multi-slice plans.

  Language is keyed off the file extension in v1 — deterministic and dependency-free. Two noted
  upgrade paths (not built): key off `ToolchainProfile` language once the any-language epic (tt6v)
  attaches it, and swap the per-line regexes for tree-sitter when precision demands it.
  """

  @max_lines 40

  @ext_lang %{
    ".ex" => :elixir,
    ".exs" => :elixir,
    ".js" => :javascript,
    ".jsx" => :javascript,
    ".ts" => :javascript,
    ".tsx" => :javascript,
    ".py" => :python
  }

  # Interface-bearing line patterns per language family. Public surface only (e.g. Elixir `def`/
  # `defmacro` but not `defp`); anchored at line start (after leading whitespace).
  @patterns %{
    elixir: [
      ~r/^\s*defmodule\s/,
      ~r/^\s*@(spec|type|typep|callback|macrocallback|behaviour)\b/,
      ~r/^\s*def(macro|delegate|guard)?\s/
    ],
    javascript: [
      ~r/^\s*export\b/,
      ~r/^\s*(export\s+)?(default\s+)?(async\s+)?function\b/,
      ~r/^\s*(export\s+)?(abstract\s+)?class\b/,
      ~r/^\s*(export\s+)?(declare\s+)?(interface|type|enum)\b/
    ],
    python: [
      ~r/^\s*(async\s+)?def\s/,
      ~r/^\s*class\s/
    ]
  }

  @doc "The language family for a path, or nil if the extension is not recognized."
  @spec language(String.t()) :: atom() | nil
  def language(path), do: Map.get(@ext_lang, path |> Path.extname() |> String.downcase())

  @doc """
  Interface-bearing lines for the file's language, joined in source order and bounded to
  `#{@max_lines}` lines. Returns nil when the language is unknown or no signatures are found, so
  the caller can fall back to a head-of-file excerpt.
  """
  @spec extract(String.t(), String.t()) :: String.t() | nil
  def extract(content, path) do
    with lang when not is_nil(lang) <- language(path),
         patterns = Map.fetch!(@patterns, lang),
         [_ | _] = lines <- signature_lines(content, patterns) do
      Enum.join(lines, "\n")
    else
      _ -> nil
    end
  end

  defp signature_lines(content, patterns) do
    content
    |> String.split("\n")
    |> Enum.filter(fn line -> Enum.any?(patterns, &Regex.match?(&1, line)) end)
    |> Enum.take(@max_lines)
  end
end
