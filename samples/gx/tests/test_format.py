"""SLICE-007 acceptance: the ``gx.report@1`` JSON envelope (AC-014, AC-015).

RED on seed: ``report.build_envelope`` is a stub, so every command's ``--format json``
path raises until SLICE-007. (The bad-format case is handled by argparse and passes on
the seed — it is a standing guard, not a slice signal.)

These tests assert the json ``data`` CONTENT, not just the envelope shape: a command
whose json branch emits reversed/empty/wrong values must fail here.
"""

from __future__ import annotations

import json

from gx import loader
from gx.commands import components, cycles, toposort
from gx.report import SCHEMA_VERSION

from conftest import CYCLIC_TXT, GRAPH_TXT, run_cli

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


def test_json_data_reflects_computation():
    """AC-014: json data carries the CORRECT computed values, not just envelope shape.

    Pins values (not arbitrary nesting) via the same keys the per-command compute tests
    already establish — so a reversed/zeroed/constant json branch is caught.
    """
    g = loader.load(str(GRAPH_TXT))

    _, env = _json("degrees")
    by_node = {d["node"]: (d["in_degree"], d["out_degree"]) for d in env["data"]["degrees"]}
    assert by_node["a"] == (0, 2)
    assert by_node["e"] == (2, 0)

    _, env = _json("toposort")
    assert env["data"]["acyclic"] is True
    assert env["data"]["order"] == toposort.compute(g)["order"]

    _, env = _json("components")
    assert env["data"]["count"] == 3
    assert env["data"]["components"] == components.compute(g)["components"]

    gc = loader.load(str(CYCLIC_TXT))
    _, env = _json("cycles", CYCLIC_TXT)
    assert env["data"]["cycles"] == cycles.compute(gc)["cycles"] == [["p", "q"], ["x", "y", "z"]]


def test_json_arrays_are_sorted():
    """AC-015: every array inside data is explicitly sorted (byte-stability prereq)."""
    _, env = _json("degrees")
    nodes = [d["node"] for d in env["data"]["degrees"]]
    assert nodes == sorted(nodes)

    _, env = _json("components")
    comps = env["data"]["components"]
    assert comps == sorted(comps)
    for comp in comps:
        assert comp == sorted(comp)

    _, env = _json("cycles", CYCLIC_TXT)
    assert env["data"]["cycles"] == sorted(env["data"]["cycles"])


def test_bad_format_exit_2():
    """AC-014: an unknown --format exits 2 (argparse usage error)."""
    code, _out, _err = run_cli(["--path", str(GRAPH_TXT), "--format", "xml", "degrees"])
    assert code == 2
