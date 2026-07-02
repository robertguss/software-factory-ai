# Dialyzer warnings suppressed as toolchain/false-positive noise. Each entry is a
# deliberate, documented suppression — not a masked defect.
[
  # Phoenix's own router macro expansion.
  {"deps/phoenix/lib/phoenix/router.ex", :pattern_match},

  # OTP `:sets`/MapSet opacity false-positive: dialyzer infers the concrete
  # `:sets` internal representation from `MapSet.new/0` instead of the opaque
  # `:sets.set()`, then flags idiomatic `MapSet.member?/2`, `MapSet.put/2`, and
  # recursive traversal calls. The code is correct; the accumulator is always a
  # MapSet. Suppressing here also avoids a dialyxir formatter crash on these
  # `call_with_opaque` messages.
  {"lib/conveyor/planning/slice_dependency.ex", :call_without_opaque},
  {"lib/conveyor/planning/slice_dependency.ex", :call_with_opaque},
  {"lib/conveyor/task_graph.ex", :call_without_opaque},
  {"lib/conveyor/task_graph.ex", :call_with_opaque},
  {"lib/conveyor_web/live/cockpit/graph_projection.ex", :call_without_opaque},
  {"lib/conveyor_web/live/cockpit/graph_projection.ex", :call_with_opaque},

  # Deterministic eval fixtures make a defensive invariant branch provably
  # constant, so dialyzer reports the `and`-expansion's `false` arm as dead.
  # The runtime check is a load-bearing scorecard invariant and must stay.
  {"lib/conveyor/eval/compiler_properties.ex", :pattern_match}
]
