# Phase 02 — foundation

Lands the **13 shared packages** (`flows/phases/02-foundation/blueprint.yaml`) that
everything later builds on. Nothing deploys and no provider connection is
needed — the PR's verify lanes (turbo builds + tests) are the whole gate.

## What it lands

`packages/`: `cli`, `contracts` (+tests), `db` (+tests),
`notifications-client` (+tests), `policy-engine` (+tests), `sdk`,
`shared`, `testing`, `webhook-verifier` — each a `turbo-package` component
whose lanes build and test it in CI.

## Inputs

`out`, `workspace`, optional `dryrun` (see [the phases README](../README.md)
— identity comes from the repo's `.rebrand/values.json`).

```bash
orun workflow run flows/phases/02-foundation/workflow.yaml \
  --set out=$HOME/sourceplane/acme --set workspace=ws_…
```

## Steps

1. **apply** — `common/apply-blueprint.sh` writes the package tree,
   rebrands it, archives the phase provenance lock. Requires a clean
   product tree (commit/stash first).
2. **land** — `common/land-pr.sh`: PR `phase(02-foundation): shared
   packages`, waits for its verify lanes, merges.
3. **converge** — waits for the merge's main run (verify lanes again on
   main; auto-resumed through transients).

## Verify / done means

The main convergence run is green — every package builds and its tests
pass in the product repo.

## Troubleshooting

- **PR lanes fail building a package**: the baseline's packages are
  self-contained; a failure here usually means a partial apply (re-run the
  phase — apply is additive) or a pnpm lock drift (the scaffold carries
  the lock; don't regenerate it mid-phase).
- **`apply-blueprint: working tree is not clean`**: commit or stash your
  local edits in the product repo first — the phase refuses to mix its
  slice with unrelated changes.

## Next

[Phase 03 — infrastructure](../03-infrastructure/README.md).
