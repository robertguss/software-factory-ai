#!/usr/bin/env python3
"""
Resumable driver that materialises the Phase 1.5 + Phase 2 bead graph in `br`.

Design:
  * Each spec module exposes BEADS = [ {label,title,type,parent,deps,priority,labels,desc}, ... ].
  * `label` is a stable key used only inside this build to express parent/dep edges;
    the real br ID is auto-generated and captured into state/label_to_id.json.
  * Hierarchy (program -> increment -> milestone -> leaf, and group-epic -> child) is
    created with `--parent <id>`, which also yields the dotted house-style IDs.
  * The blocking DAG (`deps`) is wired afterwards with `br dep add <child> <dep>` (blocks).
  * Fully resumable: already-created labels are skipped; already-wired edges are skipped;
    state is flushed to disk after every mutation so a crash never loses work.
  * `--no-auto-flush/--no-auto-import` keep each br call fast; we flush JSONL once at the end.
"""
import json, os, subprocess, sys

ROOT = os.path.dirname(os.path.abspath(__file__))
STATE = os.path.join(ROOT, "state")
os.makedirs(STATE, exist_ok=True)
ID_MAP = os.path.join(STATE, "label_to_id.json")
WIRED = os.path.join(STATE, "wired.json")
ACTOR = os.environ.get("BR_ACTOR", "robert")
PROJECT = "/home/robert/Projects/software-factory-ai"

# Spec modules, in safe import order (parents-first is enforced by depth sort anyway).
SPEC_MODULES = [
    "spec_core", "spec_adrs", "spec_schemas",
    "spec_p15a", "spec_p15b", "spec_p2a", "spec_p2b",
    "spec_canaries", "spec_deferred",
]

def load(path, default):
    if os.path.exists(path):
        with open(path) as f:
            return json.load(f)
    return default

def save(path, obj):
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(obj, f, indent=0)
    os.replace(tmp, path)

def collect_beads():
    sys.path.insert(0, ROOT)
    beads = []
    seen = set()
    for mod in SPEC_MODULES:
        try:
            m = __import__(mod)
        except ModuleNotFoundError:
            continue
        for b in getattr(m, "BEADS", []):
            lbl = b["label"]
            if lbl in seen:
                raise SystemExit(f"DUPLICATE LABEL: {lbl}")
            seen.add(lbl)
            beads.append(b)
    return beads

def depth(b, by_label, cache):
    lbl = b["label"]
    if lbl in cache:
        return cache[lbl]
    p = b.get("parent")
    d = 0 if not p else depth(by_label[p], by_label, cache) + 1
    cache[lbl] = d
    return d

def run(args):
    r = subprocess.run(["br"] + args, cwd=PROJECT, capture_output=True, text=True)
    return r.returncode, (r.stdout or "").strip(), (r.stderr or "").strip()

def create(b, id_map):
    args = [
        "create", b["title"],
        "-t", b.get("type", "task"),
        "-p", str(b.get("priority", 2)),
        "-d", b["desc"],
        "--actor", ACTOR, "--silent", "--no-auto-flush", "--no-auto-import",
    ]
    labels = b.get("labels") or []
    if labels:
        args += ["-l", ",".join(labels)]
    if b.get("status"):
        args += ["-s", b["status"]]
    parent = b.get("parent")
    if parent:
        pid = id_map.get(parent)
        if not pid:
            raise SystemExit(f"parent {parent} not yet created for {b['label']}")
        args += ["--parent", pid]
    rc, out, err = run(args)
    if rc != 0 or not out:
        raise SystemExit(f"CREATE FAILED {b['label']}: rc={rc} err={err} out={out}")
    return out.split()[-1].strip()

def main():
    beads = collect_beads()
    by_label = {b["label"]: b for b in beads}
    cache = {}
    beads.sort(key=lambda b: depth(b, by_label, cache))  # parents before children

    # validate edges
    for b in beads:
        for d in b.get("deps", []) or []:
            if d not in by_label:
                raise SystemExit(f"{b['label']} deps on unknown label {d}")
        if b.get("parent") and b["parent"] not in by_label:
            raise SystemExit(f"{b['label']} parent unknown {b['parent']}")

    id_map = load(ID_MAP, {})
    wired = set(load(WIRED, []))

    created = 0
    for b in beads:
        if b["label"] in id_map:
            continue
        nid = create(b, id_map)
        id_map[b["label"]] = nid
        save(ID_MAP, id_map)
        created += 1
        if created % 25 == 0:
            print(f"  ...created {created}")

    # wire blocking deps
    wired_new = 0
    for b in beads:
        cid = id_map[b["label"]]
        for d in b.get("deps", []) or []:
            key = f"{b['label']}=>{d}"
            if key in wired:
                continue
            did = id_map[d]
            rc, out, err = run(["dep", "add", cid, did, "--type", "blocks",
                                "--actor", ACTOR, "--no-auto-flush", "--no-auto-import"])
            if rc != 0 and "already" not in (out + err).lower():
                print(f"  WARN dep {key}: {err or out}")
            wired.add(key)
            wired_new += 1
    save(WIRED, sorted(wired))

    print(f"TOTAL beads in spec: {len(beads)}")
    print(f"Created this run: {created}  (mapped total: {len(id_map)})")
    print(f"Dep edges wired this run: {wired_new}  (total: {len(wired)})")

if __name__ == "__main__":
    main()
