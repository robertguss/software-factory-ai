# gx — directed-graph insight CLI

A read-only, hermetic CLI that answers five questions about a directed graph supplied
as a plain-text edge-list. Every answer is a pure, deterministic function of the input
bytes and the chosen `--format`. The normalized execution surface is
`conveyor.plan.yml` (`conveyor.plan@1`); this prose explains intent.

The plan declares a **branching** work-dependency graph: a loader foundation fans out
to four independent algorithm slices, which a digest composes, with a JSON-envelope +
determinism slice on top.

## Requirements

### requirement-req-001
Parse an edge-list file into a canonical, immutable `Graph`. Skip `#` comments and
blank lines; tolerate a trailing newline. A valid line is `"SRC DST"` (a directed edge)
or a single token (an isolated node). A line with three or more tokens is malformed:
exit `2` with a stderr message naming the offending 1-based line number. Nodes, edges,
and per-node adjacency are sorted.

### requirement-req-002
A `degrees` command reports each node's in-degree and out-degree, sorted by node id.

### requirement-req-003
A `toposort` command returns a topological ordering via Kahn's algorithm with a
smallest-node-id tie-break (deterministic). On a cyclic graph there is no order: it
reports the cyclic condition and exits `1`.

### requirement-req-004
A `components` command partitions nodes into weakly-connected components (each directed
edge treated as undirected). Each component is sorted; components are sorted by their
smallest member.

### requirement-req-005
A `cycles` command detects directed cycles, reporting each exactly once as its
canonical rotation (rotated to start at the cycle's smallest node id), with the list of
cycles sorted. Any cycle exits `1`; an acyclic graph exits `0`.

### requirement-req-006
A `digest` command composes summary + degrees + toposort + components + cycles into one
markdown report with a fixed section order. It reuses the other commands' `compute`
functions and is byte-stable across runs and processes.

### requirement-req-007
Every command accepts `--format markdown|json` (default markdown); `json` emits the
locked `gx.report@1` envelope `{schema_version, kind, source, data}` with sorted arrays.
An unknown format exits `2`.

### requirement-req-008
Output is a pure function of `(edge-list, --format)`. No wall-clock, environment, or
locale reads; no dependence on dict/set iteration order. Digest output is byte-identical
across two processes run with different `PYTHONHASHSEED`.

## Decisions

- **DEC-001** — Strictly read-only and hermetic: parse the edge-list bytes directly,
  no network, no clock. Makes every acceptance criterion mechanically checkable under
  the gate's hermetic pytest profile and removes nondeterminism.
- **DEC-002** — Exactly two interfaces are locked across slices: the `Graph` model and
  the `gx.report@1` JSON envelope. Evolution mints a new `@2`, never mutates `@1`.
- **DEC-003** — Single archetype (greenfield pure-logic Python, one verification
  command `pytest -q`) to keep the gate signal clean.
