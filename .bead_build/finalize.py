#!/usr/bin/env python3
"""Finalize: supersede the deferred Phase-2 placeholder sgp.1, verify the graph, flush JSONL."""
import json, os, subprocess
ROOT = os.path.dirname(os.path.abspath(__file__))
PROJECT = "/home/robert/Projects/software-factory-ai"
ACTOR = os.environ.get("BR_ACTOR", "robert")
m = json.load(open(os.path.join(ROOT, "state", "label_to_id.json")))

def run(args):
    r = subprocess.run(["br"] + args, cwd=PROJECT, capture_output=True, text=True)
    return r.returncode, (r.stdout or "").strip(), (r.stderr or "").strip()

prog, p2a, p2b = m["PROG"], m["P2-A"], m["P2-B"]
reason = (f"Superseded by the active Phase 1.5+2 program epic {prog} "
          f"(Phase-2 increments {p2a} P2-A Compiler Core, {p2b} P2-B Contract Foundry). "
          f"This one-line roadmap placeholder is replaced by the detailed bead tree.")

# 1) supersede sgp.1 (idempotent: ignore if already closed)
rc, out, err = run(["close", "software-factory-ai-sgp.1", "--reason", reason,
                    "--actor", ACTOR, "--no-auto-flush", "--no-auto-import"])
print("close sgp.1:", out or err)

# 2) cycles must be empty
rc, out, err = run(["dep", "cycles"])
print("CYCLES:", out or err)

# 3) counts
rc, out, err = run(["stats", "--json"])
try:
    s = json.loads(out)["summary"]
    print(f"STATS: total={s['total_issues']} open={s['open_issues']} blocked={s['blocked_issues']} "
          f"deferred={s['deferred_issues']} closed={s['closed_issues']} ready={s['ready_issues']}")
except Exception:
    print("stats:", out or err)

print(f"NEW BEADS MAPPED: {len(m)}")

# 4) flush JSONL so .beads/issues.jsonl reflects everything (git is the user's job)
rc, out, err = run(["sync", "--flush-only"])
print("FLUSH:", out or err)
