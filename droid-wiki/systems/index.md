# Systems

Internal building blocks of Conveyor. Each system page documents a subsystem's
directory layout, key abstractions, how it works, and entry points for
modification.

## Pages

| System | Summary |
| ------ | ------- |
| [Planning compiler](planning-compiler.md) | Lowers human-authored plans into contract-bearing work graphs and drives width-1 serial execution. |
| [Gate](gate.md) | Staged verification boundary that decides whether a slice may merge without a human. |
| [Eval framework](eval-framework.md) | Runs the factory's own pipeline against a canary corpus and grades results through the real gate. |
| [Policy engine](policy-engine.md) | Command-level safety boundary that decides whether a normalized command may run inside a sandbox. |
| [Evidence recording](evidence-recording.md) | Captures machine-readable proof of a run attempt: patches, test results, acceptance mapping, redacted artifacts. |
| [Artifact projection](artifact-projection.md) | Regenerates read-only artifact trees from database metadata and content-addressed blobs. |
| [Agent runner](agent-runner.md) | Behaviour every coding-agent backend implements; adapters include Codex, Claude, fake, and reference solution. |
| [Sandbox](sandbox.md) | Docker-based isolation layer that runs agent work in containers with network and filesystem policies. |
| [Cassettes](cassettes.md) | Records and replays agent interactions for deterministic, zero-cost verification. |
| [Qualification](qualification.md) | Manages scoped qualification grants and impact expiry that invalidates grants when evidence or policy changes. |
| [Contract forge](contract-forge.md) | Authors agent brief contracts, derives falsifier seeds, and locks interface policies before the agent is unlocked. |
| [Contract critic](contract-critic.md) | Red-teams contracts for cheapest-wrong findings, independence, and repairable defects with a bounded repair loop. |
| [Battery](battery.md) | Release report projection, live sampling, and secondary confirmation for measuring factory health over time. |
