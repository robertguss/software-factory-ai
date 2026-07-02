# Gap-log template

The gap log is the structured record of what each run taught us — the manual
precursor of the automated gap-log (Learning Flywheel epic). Keep the field
names below aligned with that auto-log so the manual entries fold in cleanly
when it lands.

Record one entry per finding (not per run): a run that parks three slices for
three different reasons is three entries.

## Fields

| Field         | Meaning                                                                                               |
| ------------- | ----------------------------------------------------------------------------------------------------- |
| `run_id`      | The run the finding came from (`conveyor.run_view <run_id>`).                                         |
| `slice`       | The slice stable key (e.g. `SLICE-003`), or `-` for run-level.                                        |
| `symptom`     | What was observed, operator-facing (e.g. "parked with `out_of_scope_path` on `__init__.py`").         |
| `layer`       | Where the root cause lives: `contract` / `gate` / `adapter` / `driver` / `policy` / `docs` / `infra`. |
| `disposition` | What was decided: `accept` / `rework` / `reject` / `park` / `false_park` / `wont_fix`.                |
| `bead_filed`  | The `br` id filed (or `-` if none / folded into an existing bead).                                    |
| `notes`       | One line of context or the corrective.                                                                |

## Template

```
- run_id:
  slice:
  symptom:
  layer:
  disposition:
  bead_filed:
  notes:
```

## Example

```
- run_id: 5d8f-...-e63b
  slice: SLICE-003
  symptom: parked with out_of_scope_path on tasks/__init__.py (a required export)
  layer: gate
  disposition: false_park
  bead_filed: negotiated-scope-nyrl.1
  notes: barrel edit not in likely_files; always-allowed classes fix this
```

## Discipline

- **A false-park is a finding, not a shrug.** If correct work was blocked, log
  it and file the bead — that is how the gate's calibration improves.
- **Name the layer honestly.** "The gate is wrong" and "the contract was wrong"
  lead to different fixes; guessing the layer wastes the next run.
- **Link the bead.** An unlinked gap log is a lesson that will be re-learned.
