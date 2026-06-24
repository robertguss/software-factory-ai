# gx — graph insight CLI (Conveyor sample plan)

A read-only, hermetic Python CLI that answers five questions about a **directed
graph** given as a plain edge-list: per-node `degrees`, a `toposort`,
weakly-connected `components`, directed `cycles`, and a composed `digest`. Pure
logic, no network, no clock, byte-stable output.

This is a Conveyor `conveyor.plan@1` sample with a **branching** work-dependency
graph: a loader foundation (SLICE-001) fans out to four mutually-independent
algorithm slices (SLICE-002..005), which a digest (SLICE-006) composes, with a
JSON-envelope + determinism slice (SLICE-007) on top. It exists to stress the
serial loop on fresh substrate and to exercise skip-and-continue when an
independent slice parks.

## Input format

One statement per line; `#` comments and blank lines are ignored:

```
a b      # a directed edge a -> b
z        # an isolated node
```

A line with three or more tokens is malformed (exit 2, naming the line number).

## Usage

```
gx --path graph.txt degrees
gx --path graph.txt --format json digest
```

Exit codes: `0` success · `1` a cyclic condition (`cycles` found, or `toposort`
on a cyclic graph) · `2` bad input / bad `--format`.

## Verify

```
pytest -q
```
