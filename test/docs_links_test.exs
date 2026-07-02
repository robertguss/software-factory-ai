defmodule Conveyor.DocsLinksTest do
  @moduledoc """
  Fail-fast link check (never-lie-mmxr.2): every intra-repo markdown link in the
  README and docs/ must resolve to a file that exists. Dead links are a truth
  defect — this runs in `mix test`, so CI catches them.
  """
  use ExUnit.Case, async: true

  @roots ["README.md", "STRATEGY.md", "ROADMAP.md", "CONCEPTS.md"]
  @link_re ~r/\[[^\]]*\]\(([^)]+)\)/

  test "every intra-repo markdown link resolves" do
    broken =
      markdown_files()
      |> Enum.flat_map(&broken_links/1)

    assert broken == [],
           "broken intra-repo markdown links:\n" <>
             Enum.map_join(broken, "\n", fn {file, target} -> "  #{file} -> #{target}" end)
  end

  defp markdown_files do
    (@roots ++ Path.wildcard("docs/**/*.md"))
    |> Enum.filter(&File.regular?/1)
    |> Enum.uniq()
  end

  defp broken_links(file) do
    base = Path.dirname(file)

    @link_re
    |> Regex.scan(File.read!(file))
    |> Enum.map(fn [_full, target] -> target end)
    |> Enum.map(&intra_repo_target/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.reject(&File.exists?(Path.expand(&1, base)))
    |> Enum.map(&{file, &1})
  end

  # Keep only intra-repo relative paths: drop external URLs, in-page anchors,
  # mailto, and any trailing `#anchor` / `"title"` on the target.
  defp intra_repo_target(target) do
    path =
      target
      |> String.trim()
      |> String.split(~r/\s+/, parts: 2)
      |> List.first()
      |> String.split("#", parts: 2)
      |> List.first()

    cond do
      path in [nil, ""] -> nil
      String.starts_with?(path, ["http://", "https://", "mailto:", "//"]) -> nil
      true -> path
    end
  end
end
