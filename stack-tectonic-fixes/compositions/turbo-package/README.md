# turbo-package

`turbo-package` is an exported Orun composition in the Stack Tectonic catalog.

## Purpose

Verify a shared package in a pnpm + Turborepo monorepo: install the workspace
with a frozen lockfile, run an optional pre-build, check the package has a
`package.json`, then build and typecheck it. Build and typecheck default to
`pnpm exec turbo run <task> --filter=./` when no command is given.

This composition only verifies — it publishes and deploys nothing.

## Contract

- **Type:** `turbo-package`
- **Path:** `compositions/turbo-package`
- **Composition:** `composition.yaml`
- **Schema:** `schema.yaml` — the authoritative parameter contract
- **Job:** `verify` (default) — `jobs/turbo-package-verify.yaml`
- **Default profile:** `verify`
- **Required parameters:** `nodeVersion`, `pnpmVersion`
- **Optional parameters:** `preBuildCommand`, `buildCommand`, `typecheckCommand`

## Profiles

Each file in `profiles/` selects steps from the job by capability.

| Profile            | Steps |
| ------------------ | ----- |
| `quick-check`      | setup-node → setup-pnpm → install → verify-structure |
| `verify` (default) | setup-node → setup-pnpm → install → pre-build → verify-structure → build → typecheck |

## Verification

`./scripts/verify.sh` is the catalog's only gate. It asserts that this
directory's `composition.yaml` has a `metadata.name` and `spec.type` matching
the directory, that `schema.yaml` and `jobs/` exist beside it, then packs the
catalog and confirms `turbo-package` exports from the packed artifact.
