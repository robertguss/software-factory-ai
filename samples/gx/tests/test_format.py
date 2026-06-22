"""SLICE-007 acceptance: the ``gx.report@1`` JSON envelope (AC-014, AC-015).

RED on seed: ``report.build_envelope`` is a stub, so every command's ``--format json``
path raises until SLICE-007. (The bad-format case is handled by argparse and passes
on the seed — it is a standing guard, not a slice signal.)
"""

from __future__ import annotations

import json

from gx.report import SCHEMA_VERSION

from conftest import GRAPH_TXT, run_cli

COMMANDS = ["degrees", "toposort", "components", "cycles", "digest"]


def _json(cmd, path=GRAPH_TXT):
    code, out, _err = run_cli(["--path", str(path), "--format", "json", cmd])
    return code, json.loads(out)


def test_each_command_emits_locked_envelope():
    """AC-014: every command's json output is the frozen gx.report@1 envelope."""
    assert SCHEMA_VERSION == "gx.report@1"
    for cmd in COMMANDS:
        _code, env = _json(cmd)
        assert set(env) == {"schema_version", "kind", "source", "data"}
        assert env["schema_version"] == "gx.report@1"
        assert env["kind"] == cmd
        assert env["source"].endswith("graph.txt")


def test_json_arrays_are_sorted():
    """AC-015: arrays inside data are explicitly sorted (byte-stability prerequisite)."""
    _code, env = _json("degrees")
    nodes = [d["node"] for d in env["data"]["degrees"]]
    assert nodes == sorted(nodes)


def test_bad_format_exit_2():
    """AC-014: an unknown --format exits 2 (argparse usage error)."""
    code, _out, _err = run_cli(["--path", str(GRAPH_TXT), "--format", "xml", "degrees"])
    assert code == 2
