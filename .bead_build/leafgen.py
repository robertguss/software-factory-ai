# -*- coding: utf-8 -*-
# Helper: expand a milestone's Deliver bullets into leaf tasks + one Definition-of-Done leaf.
# Leaves inherit their milestone's blockers (so a milestone's leaves become `ready` exactly
# when its prerequisites are met); the DoD leaf additionally blocks on all deliver leaves.
import spec_core
_MS = {b["label"]: b for b in spec_core.BEADS}

def mk(parent, area, refs, cutline, capability, deliver, accept):
    p = _MS[parent]
    pdeps = list(p.get("deps", []))
    beads = []
    deliver_labels = []
    for sub, title, what in deliver:
        lbl = f"{parent}.{sub}"
        deliver_labels.append(lbl)
        beads.append(dict(
            label=lbl, title=f"{parent}.{sub} — {title}", type="task",
            parent=parent, deps=pdeps, priority=2, labels=area + ["task"],
            desc=(f"**What.** {what}\n\n"
                  f"**Why.** Deliverable of **{p['title']}** (§18).\n\n"
                  f"**Refs.** {refs}.  **Cutline.** {cutline}.  **Capability.** {capability}."),
        ))
    acc = "\n".join(f"- {a}" for a in accept)
    beads.append(dict(
        label=f"{parent}.DoD", title=f"{parent} — Definition of Done / acceptance gate",
        type="task", parent=parent, deps=pdeps + deliver_labels, priority=2,
        labels=area + ["acceptance", "task"],
        desc=(f"# Acceptance gate — {p['title']}\n\n"
              f"Close only when **all** milestone exit criteria (§18) hold:\n\n{acc}\n\n"
              f"**Refs.** {refs}.  Blocks on every deliverable leaf of this milestone."),
    ))
    return beads
