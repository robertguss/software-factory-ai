defmodule Conveyor.Reviewer.ContainedReviewerTest do
  @moduledoc "m4b2.2: contained second-agent reviewer — stamped identity, not_assessed on garbage, read-only mount."
  use ExUnit.Case, async: true

  alias Conveyor.AgentRunner.ContainedExec
  alias Conveyor.Reviewer.ContainedReviewer

  defp context do
    %{
      dossier: "--- a/foo\n+++ b/foo\n",
      dossier_sha256: "dossier-abc",
      run_spec: %{run_spec_sha256: "sha256:rs123"},
      reviewer_session_id: "session-1",
      reviewer_profile_id: "profile-1",
      rubric_version: "reviewer@1"
    }
  end

  test "stamps trusted identity onto the agent's judgment (agent cannot forge it)" do
    verdict =
      Jason.encode!(%{"decision" => "rejected", "recommendation" => "rework", "summary" => "bad"})

    review_json =
      ContainedReviewer.review(context(), exec: fn _prompt, _ctx, _opts -> verdict end)

    # judgment from the agent...
    assert review_json["decision"] == "rejected"
    # ...but identity stamped by US, from the trusted context (raw sha, not the agent's word)
    assert review_json["run_spec_sha256"] == "rs123"
    assert review_json["dossier_sha256"] == "dossier-abc"
    assert review_json["reviewer"]["profile_id"] == "profile-1"
    assert review_json["schema_version"] == "conveyor.review@1"
  end

  test "the rendered prompt carries the dossier under the UNTRUSTED banner, not the trusted section" do
    parent = self()

    ContainedReviewer.review(context(),
      exec: fn prompt, _ctx, _opts ->
        send(parent, {:prompt, prompt})
        Jason.encode!(%{"decision" => "needs_rework"})
      end
    )

    assert_received {:prompt, prompt}
    assert prompt =~ "Untrusted"
    assert prompt =~ "--- a/foo"
    assert prompt =~ "ADVERSARIAL"
  end

  test "garbage agent output yields no decision (recorded :not_assessed downstream)" do
    review_json =
      ContainedReviewer.review(context(), exec: fn _p, _c, _o -> "I refuse to answer." end)

    # only stamped identity survives — no decision/findings/checks -> schema-invalid -> not_assessed
    assert review_json["decision"] == nil
    assert review_json["run_spec_sha256"] == "rs123"
  end

  test "the reviewer's contained workspace is mounted READ-ONLY (acceptance #2)" do
    args =
      ContainedExec.docker_args(["claude"], "/tmp/ws",
        mount_mode: :ro,
        agent_image: "img",
        user: "1000:1000"
      )

    assert "/tmp/ws:/workspace:ro" in args
    refute "/tmp/ws:/workspace:rw" in args
  end

  test "the default (implementer) mount stays read-write" do
    args = ContainedExec.docker_args(["codex"], "/tmp/ws", agent_image: "img", user: "1000:1000")
    assert "/tmp/ws:/workspace:rw" in args
  end
end
