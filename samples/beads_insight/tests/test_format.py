"""SLICE-007 acceptance: --format envelope + bad-format handling (AC-013, AC-014).

test_ready_json_schema_valid is RED on seed (ready.run is a stub). test_bad_format
exercises the CLI argument layer, which IS wired in the seed, so it may pass even on
the clean base — that is intentional: the exit-2-on-bad-format contract lives in the
CLI, not in a command body.
"""

from __future__ import annotations

import json

from br_insight import loader
from br_insight.commands import ready as ready_cmd
from br_insight.report import SCHEMA_VERSION

from conftest import AS_OF, ISSUES_JSONL, run_cli

REPORT_ARRAY_KEYS = {
    "ready": "ready",
    "cycles": "cycles",
    "epics": "epics",
    "velocity": "buckets",
    "digest": "sections",
}


def test_ready_json_schema_valid():
    """AC-013: ready --format json validates against br_insight.report@1, kind == ready."""
    graph = loader.load(str(ISSUES_JSONL))
    out = ready_cmd.run(graph, as_of=AS_OF, fmt="json", source=str(ISSUES_JSONL))
    envelope = json.loads(out)

    # Locked envelope shape: {schema_version, generated_as_of, kind, source, data}.
    assert set(envelope) == {"schema_version", "generated_as_of", "kind", "source", "data"}
    assert envelope["schema_version"] == SCHEMA_VERSION  # "br_insight.report@1"
    assert envelope["kind"] == "ready"
    assert envelope["source"] == str(ISSUES_JSONL)
    assert envelope["generated_as_of"] == AS_OF
    assert REPORT_ARRAY_KEYS["ready"] in envelope["data"]
    assert isinstance(envelope["data"]["ready"], list)


def test_bad_format_exit_2():
    """AC-014: --format xml exits 2 with stderr naming the allowed formats."""
    code, _out, err = run_cli(
        ["--path", str(ISSUES_JSONL), "--as-of", AS_OF, "--format", "xml", "ready"]
    )
    assert code == 2
    # argparse names the valid choices when rejecting an invalid one.
    assert "markdown" in err and "json" in err
