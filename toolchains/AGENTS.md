# PROJECT KNOWLEDGE BASE

## OVERVIEW

`toolchains/` contains sandbox/toolchain profiles used by Conveyor to run work
against controlled external environments.

## WHERE TO LOOK

| Task | Location | Notes |
| --- | --- | --- |
| Python runner image | `sample-python-runner/Dockerfile` | Sample execution container. |
| Toolchain profile | `sample-python-runner/profile.toml` | Runtime command/profile contract. |
| Locked deps | `sample-python-runner/requirements.lock` | Reproducible Python deps. |
| SBOM | `sample-python-runner/sbom.cyclonedx.json` | Supply-chain evidence artifact. |

## CONVENTIONS

- Treat profiles, lockfiles, and SBOMs as reproducibility artifacts.
- Keep container behavior compatible with Conveyor policy: non-root,
  least-privilege, no host credential assumptions.
- Update SBOM/lockfile evidence when changing the image dependency set.
- Keep sample toolchains small and explicit; production runner generalization
  belongs in core Conveyor modules and docs.

## ANTI-PATTERNS

- Do not add privileged container behavior, Docker socket access, or host home
  mounts to sample profiles.
- Do not use pipe-to-shell installers or network-dependent setup in a locked
  runner without updating the policy/evidence story.
- Do not treat generated SBOM contents as hand-authored documentation.
