defmodule Conveyor.Digest.RenderTest do
  @moduledoc "a3hf.1.1.3: deterministic Markdown/JSON/HTML rendering of a DigestSummary."
  use ExUnit.Case, async: true

  alias Conveyor.Digest.Render

  defp digest do
    %{
      runs: [
        %{
          run_id: "R2",
          status: :complete,
          slice_count: 3,
          dispositions: %{merged: 1, parked: 0, skipped: 1, failed: 1, in_flight: 0},
          needs_judgment: 0
        },
        %{
          run_id: "R1",
          status: :complete,
          slice_count: 3,
          dispositions: %{merged: 2, parked: 1, skipped: 0, failed: 0, in_flight: 0},
          needs_judgment: 1
        }
      ],
      totals: %{
        runs: 2,
        slice_count: 6,
        needs_judgment: 1,
        dispositions: %{merged: 3, parked: 1, skipped: 1, failed: 1, in_flight: 0}
      },
      cost: %{
        totals: %{tokens: 1000, cost_usd: 1.0, latency_ms: 10_000, count: 4},
        remaining: %{tokens: 4000, cost_usd: 1.5, over_budget?: false},
        by_run: %{},
        by_slice: %{},
        by_agent: %{},
        by_attempt: %{}
      }
    }
  end

  test "markdown is deterministic and lists runs sorted by run_id" do
    md = Render.to_markdown(digest())

    assert md =~ "# Morning Digest"
    # runs sorted: R1 before R2 regardless of input order
    assert :binary.match(md, "| R1 |") < :binary.match(md, "| R2 |")
    assert md =~ "| R1 | complete | 2 | 1 | 0 | 0 | 1 |"
    assert md =~ "**Runs:** 2"
    assert md =~ "**Needs judgment:** 1"
    assert md =~ "**Tokens:** 1000"
    assert md =~ "Remaining: 4000 tokens (budget ok)"
  end

  test "markdown rendering is stable across calls (golden-stable)" do
    assert Render.to_markdown(digest()) == Render.to_markdown(digest())
  end

  test "json round-trips to the DigestSummary structure" do
    json = digest() |> Render.to_json() |> Jason.decode!()

    assert json["totals"]["runs"] == 2
    assert json["totals"]["dispositions"]["merged"] == 3
    assert length(json["runs"]) == 2
    assert json["cost"]["totals"]["tokens"] == 1000
  end

  test "html wraps the digest in a document" do
    html = Render.to_html(digest())
    assert html =~ "<!DOCTYPE html>"
    assert html =~ "Morning Digest"
    assert html =~ "R1"
  end
end
