# Conveyor — Radical Leverage Ideas (brainstorm)

> **Date:** 2026-06-20 · **Lens:** maximize Robert's _raw solo-shipping
> leverage_ (utility-first, not a sellable moat). **Latitude:** no sacred cows —
> ideas here are allowed to overturn ratified ADRs/laws; each heresy is flagged
> with what it breaks and why it's worth it. **Method:** grounded in a full
> re-read of `droid-wiki/`, a live audit of `lib/conveyor/` seams (wired /
> stubbed / computed-then-discarded), and fresh competitor research
> (agentic-coding-flywheel, factory.ai, fabro, strongdm factory,
> Cognition/Devin, Codex subagents, SWE-agent, spec-driven tools).
>
> This is a brainstorm artifact, sibling to `BRAINSTORM.md`. It deliberately
> pushes past the existing idea catalog in `00-FIRST-LIGHT-HANDOFF.md §9–§10`
> (AttemptLoop, Rework Synthesizer, BackEdge, Scar Ledger, Sealed Verdict, etc.
> are assumed; this doc is the _next_ layer).

---

## 0. The one-paragraph thesis

Conveyor is not behind the field — it is **accidentally sitting on the field's
single hardest unsolved problem with most of the substrate already built and
dormant.** Every serious competitor (Factory.ai's roadmap, StrongDM's manifesto,
Cognition's own admission) converges on the same frontier: _trustworthy
autonomous verification and reliability when no human is watching._ That is
precisely the thing Conveyor's determinism boundary, 14-stage gate, anti-vacuity
oracle, content-addressed evidence, and cassette replay were built for — and the
production loop currently exercises **one** gate stage (`test_execution`). The
radical program is therefore **not "build more machinery." It is "activate the
machinery you already have, and point it at your own throughput."** The verifier
stops being a gate at the end and becomes a continuous oracle that drives
routing, abstention, planning, the agent's own inner loop, and your attention.

---

## 1. The competitive insight (why this is the open flank)

From the research, the field's **unsolved problems**, ranked by how much room
they leave for a verification-native BEAM system:

1. **Autonomous adjudication with no human watching.** Everyone names it; nobody
   has it. Tests/lint catch _known_ failures; nothing cheaply decides "this is
   correct, safe, and good — merge it" against _unspecified_ intent.
2. **The reliability gap (the 90/10 problem).** Cognition (Mar 2026):
   reliability is improving at ~**half** the rate of raw accuracy. A 90%-success
   agent that fails _unpredictably_ on the other 10% is "a useful assistant yet
   an unacceptable autonomous system." Almost nobody designs for **calibrated
   abstention** ("I don't know — escalate this one").
3. **Spec under-specification → self-amendment.** "Converge on scenarios" only
   works if scenarios are complete. The loop nobody closes: _failed verification
   → automatic spec/contract amendment._
4. **Convergence at width > 1.** Racing N approaches and _converging them into
   one shippable result_ is Factory's future roadmap, not shipped — because
   nobody has a trustworthy automatic judge.
5. **Cost / leverage governance.** Flywheel ignores cost; StrongDM celebrates
   spend ("$1k/day/engineer"). Nobody meters **value-per-token** for one dev.
6. **Trust-calibrated selective intervention.** fabro's "intervene only where it
   matters" is right, but the intervention points are hand-placed, not computed
   from risk/uncertainty.
7. **Durable, resumable long-horizon execution.** Hours-to-days runs imply
   crash/restart recovery — **OTP/BEAM's home turf**, where the Python/cloud
   incumbents are structurally weak.
8. **Verifying "good," not just "correct."** Passing tests ≠ good code
   (Cognition's FrontierCode). No one gates on architectural fit.

**Conveyor's structural edge against each:** the determinism boundary + a real
deterministic gate (1,4,8), event-sourcing + content-addressing + per-process
isolation (2,7), `PlanAmendments`/derivation graph (3), the cost ledger (5), and
the dormant trust/calibration signal already computed (2,6). **No single player
occupies this intersection.** The catch: it's almost all _built and unused._

---

## 2. The three reframes (heresies) that organize everything

Before the ideas, three foundational shifts. Each challenges something ratified.

- **H1 — The gate is ternary, not binary.** Today: pass/fail. Heresy: **pass /
  fail / ABSTAIN.** The most valuable output of a verifier optimizing for _your
  attention_ is "I am not calibrated-confident about this one." This challenges
  the implicit "fail-closed binary" framing and makes the parked queue a
  _calibrated triage list_ instead of a dumping ground. (Ideas 1, 9, 15.)

- **H2 — The verifier is an engine, not a product.** The BRAINSTORM thesis is
  "verifier-as-product / the Genome is the moat." Under _raw leverage_, that's
  the wrong objective: the verifier's job is to **let you stop reviewing code.**
  Every "sellable artifact" idea (DSSE bundles, Vacuity-as-a-Service, Negative
  Provenance for customers) is deprioritized in favor of throughput. The Genome
  is _your_ second brain, not an asset to license. (Reframes all of Cluster C.)

- **H3 — Planning is the highest-leverage thing to pull _into_ the factory.**
  Ratified decision 6c says planning stays external/manual for v1. Heresy: for a
  _solo_ dev, executing slices faster is not the bottleneck — turning rough
  intent into a great contract-bearing plan _without hand-authoring 3,000 lines_
  is. The contract-forge + 10-lens critic + `needs-clarification` readiness
  status are already the machinery for this. (Idea 6.)

---

## 3. The full sweep (clustered)

One line each; grounding in parentheses. Deep dives for the starred (★) ones in
§4.

**Cluster A — Activate the verifier as live intelligence (the bullseye)**

1. ★ **Calibrated Abstention / Reliability Engine** — fuse `IntegritySentinel`'s
   10 probes + acceptance calibration + replay diagnostics into a calibrated
   `TrustScore`; gate emits pass/fail/**abstain**.
   (`verification/integrity_sentinel.ex`)
2. ★ **Verifier-in-the-loop as an agent tool** — expose the pure gate stages as
   a cheap mid-flight self-check the agent calls _during_ generation.
   (`gate/stages/*`)
3. **IntegritySentinel turned outward** — run the anti-vacuity oracle on _your
   own_ repos to flag tests that decayed into tautologies.
   (`integrity_sentinel.ex`)
4. **Shadow-mode gate evolution** — promote new/stricter gate stages from
   advisory→blocking only after measuring their false-positive rate on live
   runs. (resurrects dormant `shadow_controls.ex`)
5. **Verify "good" not just "correct"** — gate on consistency with ratified
   decisions in the decision/derivation graph, not just green tests.
   (`CodeScent` + decision graph, ADR 16)

**Cluster B — Collapse the rework loop / raise pass@1**

6. ★ **Speculative parallelism (race N → gate picks winner)** — N agents on the
   _same_ slice in isolated sandboxes; only the cheapest-that-passes merges.
   **Challenges Law 27 (width-1).** (real Docker `sandbox/`, the gate as judge)
7. **Calibrated model routing** — Readiness-Oracle predicts `P(pass)` per
   (archetype, model, effort); dispatch the cheapest likely one-shot. (Genome)
8. **Explorer recon agents** — `ContextScout` is already 80% of Codex's
   read-only "explorer"; make it agentic to de-risk the write agent.
   (`context_scout.ex`)
9. **Falsifier Forge upstream of spend** — prove ACs red-on-base at lock time,
   before any tokens. (resurrects `contract_forge/falsifier_seed_deriver.ex`)

**Cluster C — Memory as _your_ accelerant (Genome reframed, H2)**

10. ★ **The queryable Second Brain** — `memory_refs` + BackEdge + resurrected
    `Retrospective` → an NL-queryable graph of _why this code is correct, what
    we rejected, how it failed here before._ (3 dead seams: `run_prompt.ex:27`,
    `retrospective.ex`, `local_disk.ex:137`)
11. ★ **Failure-taxonomy auto-routing** — the `Retrospective.build!` failure
    taxonomy (computed, written to disk, _never read back_) becomes the recovery
    brain: each failure class routed to its fix. (`retrospective.ex`)
12. **Negative knowledge / anti-corpus** — inject "don't do X; we tried, fails
    AC-Y" (critic-rejected alternatives + caught mutants) into future prompts.
13. ★ **Regression Genome + replay-against-new-model** — every green run is a
    permanent $0 re-runnable test; when a better model ships, replay _parked/
    failed_ slices through it for free to auto-clear backlog.
    (`replay_engine.ex` generation/evaluation-surface split)
14. **Robert's judgments train the oracle** — every override of an abstention is
    a labeled calibration example that tunes `TrustScore`. (closes H1's loop)

**Cluster D — Leverage governance & attention (you are the scarce resource)**

15. ★ **`conveyor watch` — the ambient teammate** — factory watches your plan
    docs/repos, does work proactively, pings you ONLY for abstentions, proposed
    amendments, and green-ready PRs. The inbox _is_ the UI. (fabro's selective
    intervention, computed by confidence)
16. ★ **The Leverage Governor (value-per-token)** — closed-loop: escalate model
    only when predicted necessary, parallelize only when EV justifies, STOP when
    marginal cost > marginal value. (`policy/run_budget_guard.ex` + Genome)
17. **Trust card per PR** — one-glance "why trust this": ACs covered, mutants
    that _would_ have caught regressions, TrustScore, diff-scope proof. Turns
    your review from reading code → reading evidence. (Sealed Verdict, reframed)
18. **Human-equivalent-hours meter** — track leverage delivered (Cognition's
    metric) so you can _see_ it compounding. (`statistics.ex`)
19. **Risk-tiered "good enough" stopping** — low-risk slices stop at first
    green; high-risk keep racing/hardening. (`gate/stages/observed_risk.ex`)

**Cluster E — Close the spec-gap loop (unsolved #3, H3)**

20. ★ **Self-amending plan** — failed verification that reveals a _bad contract_
    (not bad code) auto-proposes a plan amendment + selective re-derive; you
    one-click adjudicate. (fully-wired-but-dormant-in-loop `plan_amendments.ex`,
    `invalidation_preview.ex`, selective recompilation)
21. ★ **Plan Foundry — pull planning in, interrogate you** — paragraph of intent
    → factory drafts plan via contract-forge, runs 10-lens critic, asks you only
    the genuine ambiguities. **Challenges decision 6c.** (`contract_forge/`,
    `contract_critic/`, `readiness.ex` `:needs_clarification`)
22. **Bidirectional plan↔graph sync** — amendments write back to your markdown
    constitution so your source-of-truth never drifts. (derivation graph,
    ADR 16)
23. **Contract-authorability as auto-split** — slices that can't get a crisp
    machine-checkable contract are auto-decomposed (`:too_large`).
    (`readiness.ex`)
24. **Interrogator agent** — minimal disambiguating questions before burning
    tokens. (`:needs_clarification`)

**Cluster F — Debugging god-mode & durability (BEAM's home turf)**

25. ★ **Divergence Bisector — git-bisect for the agent's mind** — when a slice
    that went green now fails, bisect the _causal event log_ to the one
    decision/tool-call that diverged. (`cassettes/replay_diagnostics.ex`
    compare)
26. **Time-travel run viewer** — scrub any run's event log in LiveView; see
    exactly what the agent saw/did at each step. (event-sourcing payoff)
27. **Crash-safe resumable long-horizon runs** — every station a durable Oban
    job; a run survives reboot, resumes from last durable state. (the structural
    edge over cloud incumbents; ADR 08 leases/fencing)
28. **Self-healing watchdog** — detect no-git/no-gate progress within timeout →
    escalate ladder or park. (BEAM-native supervision)

**Cluster G — Bold / recursive**

29. ★ **Self-hosting: Conveyor builds Conveyor** — point the loop at the repo's
    own `.beads/` ready queue. The real forcing function, not a toy CLI.
30. **Semantic merge queue** — resolve conflicts by re-running the gate on the
    merged result, not textual 3-way merge. (convergence, unsolved #4)
31. **One-command bootstrap** `mix conveyor.run PLAN` — table-stakes operator
    path; today it only runs from test files + a 6-env-var incantation.
32. **Hermetic-by-default** — switch the toolchain runner to the `:docker`
    backend (`--network=none`, pinned image) so "passes local, fails gate" and
    "the tests could phone home" both vanish. (`eval/toolchain_runner.ex`)

---

## 4. Deep dives — the top 12 (ranked within, optimized for raw leverage)

Template: _the radical move · grounded in · why it's leverage · what it
challenges · effort/risk · depends on._

### 1. The Reliability Engine — a calibrated `TrustScore` and a gate that can ABSTAIN ★ (the keystone)

- **The radical move.** Stop treating the gate as binary. Compute, per attempt,
  a calibrated `P(this verdict is actually right)` and let the loop **abstain**
  (park for you) when confidence is low — even if tests are green. Conversely,
  auto-merge only above a confidence threshold _you_ set and that the system
  _earns_.
- **Grounded in.** The signal is **already computed and thrown away.**
  `IntegritySentinel` (`lib/conveyor/verification/integrity_sentinel.ex`) runs
  10 anti-vacuity probes (base calibration, falsifier survival, hermeticity,
  repeatability, mapping, mount-boundary, source-mutation, hidden-dependency,
  falsifier-preservation) and produces a `verdict` — but it "records
  trustworthiness," it doesn't _drive_ anything. Add acceptance calibration
  (`acceptance_calibration.ex`), baseline health (`baseline_health.ex`), replay
  divergence (`cassettes/replay_diagnostics.ex`), and the Genome's historical
  pass-rate for this slice archetype. Fuse → a single Brier-calibrated score.
- **Why it's leverage.** This is the **exact** thing the whole field admits is
  missing (the 90/10 reliability gap). For you solo: you stop reviewing the 90%
  the machine is calibrated-sure about and look _only_ at the 10% it honestly
  flags. Your attention goes where uncertainty actually is. This is the
  difference between "fast at being wrong" and "trustworthy unattended."
- **What it challenges.** The binary gate framing (H1). Nothing in the ADRs
  forbids a third outcome; this _strengthens_ fail-closed (abstain is the
  ultimate fail-closed).
- **Effort/risk.** Medium. The probes exist; the work is fusion + calibration +
  threshold plumbing + an `:abstain` outcome in the finalizer. Risk: calibration
  needs data (bootstrap conservative — abstain a lot, loosen as the corpus
  grows).
- **Depends on.** Nothing hard. Compounds with #10 (Genome history) and #14
  (your overrides as labels).

### 2. Verifier-in-the-loop — gate-grade self-check as a tool the agent calls mid-flight ★

- **The radical move.** Today the agent codes blind for ~10 minutes, _then_ the
  gate judges. Instead, expose a **fast, deterministic subset of the gate** as a
  tool the agent can call _during_ generation: "which ACs am I currently
  failing? is my diff in scope? did I touch a locked path?" The agent gets
  gate-grade feedback _before_ it finishes, collapsing the rework loop into
  attempt 1.
- **Grounded in.** The gate stages (`lib/conveyor/gate/stages/*`) are pure and
  deterministic — `diff_scope`, `acceptance_mapping`, `contract_lock`,
  `secret_safety`, `test_execution` can be run incrementally on the in-progress
  workspace. The `AgentRunner` behaviour already passes `policy` + `opts`; add a
  conductor-mediated callback channel (the agent never gets authority — it gets
  a _read_ of the authoritative verifier).
- **Why it's leverage.** Pass@1 is the single biggest lever on your throughput;
  every avoided rework round is ~10 min + tokens saved. This is also the
  cheapest way to make a mediocre model behave like a better one (it
  self-corrects against ground truth instead of guessing).
- **What it challenges.** A _strict_ reading of the determinism boundary
  ("agents own judgment, conductor owns verdicts"). But this **preserves** it:
  the verdict is still the conductor's; the agent merely gets to _see_ the
  deterministic signal, like a compiler error. Flag as an explicit boundary
  clarification.
- **Effort/risk.** Medium-high (needs the gate stages to run incrementally +
  cheaply, and a safe agent↔conductor query channel). Risk: agent overfits to
  the self-check — mitigate by keeping red-team/mutation stages _out_ of the
  mid-flight subset (it can see "are ACs green," not "would mutants catch you").
- **Depends on.** Per-slice gate scoping (M1b, in progress).

### 3. Speculative parallelism — race N approaches, let the gate pick the winner ★ (heresy: width-1)

- **The radical move.** For a hard or high-risk slice, spawn **N agents in
  parallel isolated sandboxes** (different models/efforts/seeds) on the _same_
  slice. Run every result through the gate. **Merge the cheapest one that
  passes.** This is width > 1 with _zero_ merge hell (only the winner merges,
  all contend for one slice) and _zero_ coordination layer (no Agent Mail, no
  file reservations — the gate is the arbiter).
- **Grounded in.** The real Docker `Sandbox` (`lib/conveyor/sandbox/`) already
  gives isolated per-agent workspaces; the deterministic gate is exactly the
  trustworthy automatic judge that Factory.ai roadmaps and StrongDM asserts but
  nobody has. BEAM `Task`/`DynamicSupervisor` makes N concurrent runs trivial.
- **Why it's leverage.** This is **parallelism for reliability, not throughput**
  — it directly attacks the 90/10 problem by converting "this model fails
  unpredictably 10% of the time" into "P(all N fail) is tiny." For you: hard
  slices that would've parked or rework-looped now one-shot. Governed by the
  cost meter (#16) so you only race when EV justifies it.
- **What it challenges.** **Law 27 (implementation width = 1).** But it
  challenges it in the _safest possible direction_: width on a single slice for
  first-to- green, not a fleet across slices. The "no merge queue / manual
  merge" stance survives — there's still one winning diff per slice.
- **Effort/risk.** Medium. The pieces exist; the work is a `RaceConductor` +
  winner-selection policy + cost gating. Risk: cost blowup → bound N by risk
  tier and the Leverage Governor.
- **Depends on.** #16 (cost governance) to be safe; #1 (to pick the _most
  trustworthy_ winner, not just first-green).

### 4. The Self-Amending Plan — failed verification → auto contract amendment ★ (heresy: spec-gap)

- **The radical move.** When a slice fails the gate in a way that reveals the
  **contract** is wrong (an AC that's impossible, contradictory, or under-
  specified) rather than the code, the loop **proposes a plan amendment
  automatically**, computes the blast radius, re-derives only the affected
  slices, and surfaces it to you as a one-click decision. The factory notices
  the _plan_ is wrong, not just the code.
- **Grounded in.** This is **fully wired and dormant in the loop.**
  `PlanAmendments.propose/1` (`lib/conveyor/planning/plan_amendments.ex`)
  already calls `InvalidationPreview.preview_invalidation` +
  `ImpactPreview.build` and returns `affected_refs` / `downstream_refs` /
  `invalidated_artifact_refs` / `status` (`:accepted` |
  `:human_review_required`). Selective recompilation and the derivation graph
  (ADR 14/16) already exist. Nobody calls this from a gate failure.
- **Why it's leverage.** This closes the loop **no competitor closes** (unsolved
  #3). For a solo dev it's enormous: your plan _improves as the factory runs_,
  and you adjudicate spec changes (the genuinely high-value decisions) instead
  of debugging code to satisfy a spec that was wrong. Your initial plan no
  longer has to be perfect.
- **What it challenges.** The implicit "the plan is frozen, the agent conforms"
  model. Pair with H3. Guardrail: amendments are _proposed_, never auto-applied
  to acceptance contracts (preserves separation of duties — the implementer
  still can't rewrite its own contract; _you_ approve).
- **Effort/risk.** Medium. The proposal engine exists; the work is the
  failure→amendment classifier (which gate findings indicate a contract bug vs a
  code bug) + the approval UX. Risk: mis-classifying code bugs as spec bugs →
  keep it conservative + always human-approved at first.
- **Depends on.** A failure-taxonomy signal (#11) to classify the finding.

### 5. Plan Foundry — pull planning into the factory and interrogate you ★ (heresy: decision 6c)

- **The radical move.** Invert the contract. Today: _you_ hand-author a finished
  3,000-line plan. Instead: you give a **paragraph of intent**; the factory uses
  its contract-forge + critic machinery to draft the full plan (epics, slices,
  contracts, ACs), runs the 10-lens adversarial critic on its _own_ draft, and
  **interrogates you only on the genuine ambiguities** it can't resolve.
- **Grounded in.** All the machinery exists, pointed the wrong way:
  `contract_forge/` (drafts AgentBriefs from requirements, 7 archetype
  templates), `contract_critic/` (10 required lenses incl. intent_fidelity,
  scope_delta, hidden_decision, approval_cognitive_load), and `readiness.ex`'s
  `:needs_clarification` status — a built-in slot for "ask the human." Today
  these run on a plan you already wrote; run them on a plan the _factory_
  drafts.
- **Why it's leverage.** **This is the single biggest solo-leverage win in the
  whole doc.** Executing slices faster has diminishing returns; the bottleneck
  for one person is turning fuzzy intent into a great contract-bearing plan.
  This moves you from "spend a day authoring a spec" to "answer 5 sharp
  questions." It also makes every other idea here trigger from a sentence.
- **What it challenges.** **Ratified decision 6c** (planning is external/manual
  for v1) and **6d/Test-Architect separation** (carefully: the _factory_ drafts,
  the _critic_ (different actor) challenges, _you_ approve — separation of
  duties is preserved because the implementer is still a third actor
  downstream).
- **Effort/risk.** High (it's a real subsystem) but high-reward, and most parts
  exist. Risk: a bad auto-plan wastes a run — mitigate with the critic gate +
  your approval before execution (the existing single approval checkpoint).
- **Depends on.** The 10-lens critic being trustworthy on generated (not just
  human) plans; the interrogation UX.

### 6. The Queryable Second Brain — resurrect the three dead Genome seams ★

- **The radical move.** Every gate-verified run mints immutable
  `intent ↔ code ↔ verdict ↔ scar` edges; slice N+1's prompt is auto-seeded from
  proven neighbors _and_ critic-rejected alternatives; **and you can query it in
  natural language** ("why is this function shaped this way? what did we reject
  here? what's failed in this module before?"). The factory becomes an oracle
  about its own decisions.
- **Grounded in.** Three capabilities **computed and discarded today**:
  `memory_refs` (`factory/run_prompt.ex:27`, `prompt_builder.ex:43`) always
  defaults to `[]`; `Retrospective.build!` (`retrospective.ex`) computes a rich
  record (timings, cost, adapter friction, **failure taxonomy**, rework handoff)
  that is written to `artifacts/projector/local_disk.ex:137` and **never read
  back**; `CodeImpactOverlay` is fully implemented but `:advisory` /
  `authority_effect: :none`. Plus the event-sourced ledger is the perfect
  substrate. Promote the overlay's _inverse_ (gate-verified edges) and fill
  `memory_refs`.
- **Why it's leverage.** Under H2 this is _your_ institutional memory, not a
  moat to sell: the most direct `pass@1` lever (Genome-seeded context) **and** a
  tool that answers your "why is this like this?" questions instantly. Compounds
  with every run — a better base model still starts from zero scar tissue on
  _your_ code.
- **What it challenges.** Nothing ratified; it activates dormant seams. (It does
  reframe the "moat" framing per H2.)
- **Effort/risk.** Medium (BackEdge minting + memory selector + NL query). Risk:
  low; start by simply _reading back_ the retrospective into the next prompt.
- **Depends on.** Nothing hard; #1 and #11 both consume it.

### 7. Failure-Taxonomy Auto-Routing — make the discarded Retrospective the recovery brain ★

- **The radical move.** `Retrospective.build!` already computes a **failure
  taxonomy** (Brief Failure · Context-Pack Miss · Execution Failure · Validation
  Failure · Review Failure · Memory Failure · Policy Failure). Wire it to
  _drive_ recovery: Context-Pack Miss → re-scout; Brief Failure → propose
  amendment (#4); Execution Failure → retry with escalation; Policy Failure →
  park. Each failure class routes to its specific fix instead of a blind retry.
- **Grounded in.** `retrospective.ex` (computes the taxonomy) + the
  finalizer/rework path (`gate/finalizer.ex`) + the future AttemptLoop. The
  taxonomy is the missing _router_; it's computed and thrown away.
- **Why it's leverage.** Blind retries waste tokens and time; _targeted_
  recovery resolves failures in the cheapest correct way. This is what makes
  unattended operation actually converge instead of thrash.
- **What it challenges.** Nothing; activates dormant computation.
- **Effort/risk.** Low-medium. The classifier exists; wire it to actions.
- **Depends on.** AttemptLoop/Rework Synthesizer (handoff §9, in progress);
  feeds #4.

### 8. `conveyor watch` — the ambient teammate (the inbox is the UI) ★

- **The radical move.** Reframe the entire operator experience around **your
  attention as the scarce resource.** Instead of you driving runs, the factory
  _watches_ your plan docs (and optionally real repos), proactively does ready
  work, and pings you on **only three things**: (a) calibrated abstentions (#1),
  (b) proposed plan amendments (#4), (c) green PRs ready to merge with a trust
  card (#17). A single triage stream — the morning digest + Needs-a-Human inbox
  become the _primary_ interface.
- **Grounded in.** Phoenix LiveView + PubSub (already the observability layer),
  the parked-queue concept, the digest, `br`/`.beads/` as the ready-work source.
  fabro's "intervene only where it matters," but the intervention points are
  **computed by confidence**, not hand-placed.
- **Why it's leverage.** This is the difference between "a tool you operate" and
  "a teammate that pings you." For a solo dev, the win is _not having to think
  about the factory_ until it needs a decision only you can make. It makes every
  other feature here felt rather than theoretical.
- **What it challenges.** Nothing ratified; it's the UX expression of H1.
- **Effort/risk.** Medium (a watcher + the triage UI). Risk: noise → gate the
  pings on calibrated confidence so the inbox stays small and trustworthy.
- **Depends on.** #1 (abstention is what makes the inbox _calibrated_).

### 9. The Leverage Governor — value-per-token closed loop ★

- **The radical move.** A governor that, per slice, chooses the **cheapest path
  to green**: pick the cheapest model the Readiness Oracle predicts will
  one-shot (#7), escalate model/effort only when predicted necessary, race N
  (#3) only when expected value justifies the spend, and **stop** when marginal
  cost > marginal value. Cost becomes an _optimizer input_, not a fear or a
  vanity metric.
- **Grounded in.** `policy/run_budget_guard.ex` already tracks tokens/cost
  across 10 caps and can transition runs to `:exhausted`; the Genome supplies
  the P(pass) priors; `observed_risk` supplies the risk tier.
- **Why it's leverage.** Everyone else ignores cost (Flywheel) or celebrates
  spend (StrongDM's "$1k/day"). For a solo dev, **value-per-token** is the
  actual objective — this maximizes shipped-per-dollar automatically and makes
  aggressive features (#3) safe to enable.
- **What it challenges.** Nothing ratified (BRAINSTORM already wants an economic
  governor; this makes it a _closed loop_, not a report).
- **Effort/risk.** Medium. Risk: bad priors early → conservative defaults, learn
  from the corpus.
- **Depends on.** #6/#7 (Genome priors).

### 10. Regression Genome + Replay-Against-New-Model ★

- **The radical move.** Two compounding superpowers from one mechanism: (a)
  **every green run becomes a permanent, $0, deterministic regression test**
  that re-verifies against the _current_ gate; when you tighten a contract or
  add a gate stage, the whole history re-validates offline and flags "this used
  to pass but wouldn't now." (b) **When a better model ships, replay your
  _parked/failed_ slices through it for free** (generation-surface unchanged) to
  see which now pass — your hard-work backlog auto-clears as models improve,
  without re-running everything.
- **Grounded in.** `cassettes/replay_engine.ex` has the **generation-surface vs
  evaluation-surface digest split** — exactly what lets a recorded run be
  re-verified against a _new_ evaluation surface for $0. Nobody else in the
  field has this split.
- **Why it's leverage.** Your regression safety net scales with output at zero
  marginal cost, and your backlog of hard slices becomes self-clearing on model
  upgrades. Both are pure compounding leverage.
- **What it challenges.** Nothing; activates an existing superpower.
- **Effort/risk.** Medium. Record the verdict + evaluation_surface_digest with
  each cassette; build the re-verify sweep.
- **Depends on.** Cassette recording in the production loop.

### 11. Divergence Bisector — git-bisect for the agent's mind ★

- **The radical move.** When a slice that used to go green now fails, **bisect
  the causal event log** across runs to pinpoint the single decision/tool-call
  where behavior diverged — and surface "here's the one step where it went
  wrong" instead of a 50-file diff.
- **Grounded in.** `cassettes/replay_diagnostics.ex` `compare` is already a
  first-divergence finder across the causal sequence + tool contracts +
  normalized args. Event-sourcing + content-addressing make this uniquely
  possible here.
- **Why it's leverage.** Debugging is the #1 time sink for a solo dev driving a
  width-1 loop. This turns "why did this break?" from hours to seconds — the
  highest-leverage _developer-experience_ multiplier on every other feature.
- **What it challenges.** Nothing; packages an existing capability.
- **Effort/risk.** Low-medium (mostly UX + cross-run anchoring).
- **Depends on.** Cassette recording.

### 12. Self-Hosting — point Conveyor at its own `.beads/` ★ (bold/recursive)

- **The radical move.** Stop proving the factory on a toy CLI. **Feed Conveyor's
  own ready beads through the loop** — have the factory build the factory. The
  Beads Insight CLI was a hermetic forcing function; the real one is this repo.
- **Grounded in.** `.beads/` is already the project's source of truth
  (AGENTS.md); `br ready --json` already yields the work queue.
- **Why it's leverage.** The ultimate dogfood: every reliability/abstention/cost
  feature becomes _real_ because the stakes are your actual project, and each
  feature that lands immediately accelerates building the next one — a literal
  flywheel. It's also the most honest possible test of "can I trust this
  unattended?"
- **What it challenges.** Prudence (Elixir/Ash is a harder target than a
  hermetic Python CLI; a bad auto-merge hurts the real repo). **Flag: gate hard,
  abstain generously, manual-merge only at first.**
- **Effort/risk.** High risk, highest payoff. Stage it: read-only/advisory runs
  first (the factory _proposes_ PRs you review), earn auto-merge over time.
- **Depends on.** #1 (abstention) + #11 (bisector) to be safe; basically the
  capstone that consumes everything above.

---

## 5. The bets — recommended sequence (a coherent build order)

Not just a ranking — a _dependency-aware path_ where each rung makes the next
safer and is independently useful.

1. **#1 Reliability Engine (calibrated abstention).** The keystone. Everything
   else (ambient teammate, racing, self-hosting) needs "the machine knows when
   it doesn't know." It's also the field's #1 unsolved problem and you have the
   substrate. _Start here._
2. **#6 Queryable Second Brain + #7 Failure-Taxonomy Routing.** Resurrect the
   three dead seams. Cheap, pure leverage, and they feed #1's calibration and
   #4's classification. (This is the "free energy" — capability you already paid
   for.)
3. **#2 Verifier-in-the-loop self-check.** The biggest pass@1 lever; collapses
   rework into attempt 1.
4. **#4 Self-Amending Plan + #5 Plan Foundry.** Close the spec-gap loop and move
   your effort from authoring specs to answering questions — the largest pure
   solo-leverage gain. (Heresies H3/6c.)
5. **#9 Leverage Governor → then #3 Speculative Parallelism.** Governance first
   so racing is safe; then race for reliability on hard slices. (Heresy:
   width-1.)
6. **#8 `conveyor watch` + #11 Divergence Bisector.** The attention layer and
   the debugging multiplier — make the whole thing _felt_ and operable.
7. **#10 Regression Genome / replay-against-new-model.** Compounding safety + a
   self-clearing backlog as models improve.
8. **#12 Self-Hosting.** The capstone and the truest test. Earn it last.

**The through-line:** #1 makes the machine _honest about its uncertainty_; #2/#3
make it _more often right_; #4/#5 make _your intent_ the input; #6/#7/#10 make
success _compound_; #8/#11 make it _legible_; #12 turns it on _yourself_. None
of this is "build more verification" — it is **activate the verification you
already built and aim it at your throughput.**

---

## 6. Appendix — the dormant substrate (the free energy)

Capability already built and _not_ used in the loop — the cheapest leverage in
the codebase because you've already paid for it:

| Dormant seam                                     | Location                                           | Status                                 | Activated by                     |
| ------------------------------------------------ | -------------------------------------------------- | -------------------------------------- | -------------------------------- |
| `IntegritySentinel` (10-probe oracle)            | `verification/integrity_sentinel.ex`               | records trust, drives nothing          | #1                               |
| `Retrospective.build!` (incl. failure taxonomy)  | `retrospective.ex` → `local_disk.ex:137`           | written, never read                    | #6, #7                           |
| `memory_refs`                                    | `factory/run_prompt.ex:27`, `prompt_builder.ex:43` | always `[]`                            | #6                               |
| `CodeImpactOverlay`                              | `planning/code_impact_overlay.ex`                  | `:advisory`, `authority_effect: :none` | #6 (promote inverse)             |
| `PlanAmendments.propose`                         | `planning/plan_amendments.ex`                      | wired, never called from gate-fail     | #4                               |
| `ReplayEngine` gen/eval-surface split            | `cassettes/replay_engine.ex`                       | replay exists, $0 re-verify unused     | #10                              |
| `ReplayDiagnostics.compare`                      | `cassettes/replay_diagnostics.ex`                  | divergence finder, no UX               | #11                              |
| `ShadowControls` (Tutor)                         | `shadow_controls.ex`                               | `advisory_only`, decides nothing       | #4 of §3 (shadow gate evolution) |
| 13 of 14 gate stages                             | `gate/stages/*`                                    | only `test_execution` in the loop      | #2, M3                           |
| `contract_forge` + `contract_critic` (10 lenses) | `contract_forge/`, `contract_critic/`              | run on human plans only                | #5                               |
| `:needs_clarification` readiness                 | `readiness.ex`                                     | status exists, no interrogator         | #5, §3-24                        |
| Layered roots (4 families)                       | `planning/layered_roots.ex`                        | single-root only in Phase 1            | (future)                         |
| Qualification gate (pure, 15 blockers)           | `qualification/`                                   | runtime-only, deferred                 | (future)                         |

**Headline:** the production loop runs ~1/15th of the gate and ignores the trust
oracle, the failure taxonomy, the amendment engine, the replay superpower, and
the whole contract-authoring brain. The radical roadmap above is mostly
**wiring, not building.**
