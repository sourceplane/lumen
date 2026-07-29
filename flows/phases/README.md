# Phased bootstrap — one workflow per phase

Seven independent workflows that take a product from **nothing** to a
**live baseline**, one slice at a time, at whatever pace you choose. Each
phase is self-contained and follows the same contract:

> **apply its blueprint slice → land it as a PR → watch the deployment
> convergence (auto-resumed) → verify it is actually deployed.**

Run every workflow **from the baseline checkout** (the blueprints live
here); the product repo is wherever `out` points.

## Execution order

The phase number is the EXECUTION order — the root scaffold (phase 01,
historically the "workspace" blueprint) must exist before anything else
can build or deploy:

Each phase folder is fully self-contained: `README.md` + `workflow.yaml`
+ its `blueprint.yaml` (the slice it applies).

| # | folder | lands | verified by |
|---|--------|-------|-------------|
| 01 | [`01-scaffold`](01-scaffold/README.md) | **GitHub repo created** + repo born: intent, CI, flows, tooling, identity | repo pushed + workspace-linked |
| 02 | [`02-foundation`](02-foundation/README.md) | 13 shared packages | verify lanes green |
| 03 | [`03-infrastructure`](03-infrastructure/README.md) | kv, supabase, db-migrate, hyperdrive | published `WIRING_*` / `SUPABASE_*` secrets |
| 04 | [`04-workers`](04-workers/README.md) | the 12-worker fleet (two landings) | convergence green, bindings restored |
| 05 | [`05-edge`](05-edge/README.md) | api-edge | `/health` 200 on stage+prod |
| 06 | [`06-console`](06-console/README.md) | web console | console + edge live |
| 07 | [`07-domain`](07-domain/README.md) | custom domain (OPTIONAL) | convergence green |

## Inputs

Phase 01 takes the product identity once and writes it into the repo
(`.rebrand/values.json`). Every later phase reads it back and needs only:

- `out` — absolute path of the product repo
- `workspace` — workspace id (`ws_…`) or slug
- `dryrun` — `"true"` previews the phase with zero side effects (the
  blueprint is applied in the working tree, shown, and reverted; no PR, no
  deploy, nothing pushed)

```bash
orun workflow run flows/phases/03-infrastructure/workflow.yaml \
  --set out=$HOME/sourceplane/acme --set workspace=ws_… [--set dryrun=true]
```

## Pacing, idempotence, resume

- Run one phase today and the next whenever. Nothing expires between
  phases; each phase's preflight re-verifies workspace readiness.
- Every phase is **idempotent**: re-running a completed phase re-applies
  the blueprint (additive, no-op on unchanged files), finds nothing to
  land, and re-verifies. A phase that failed partway resumes by simply
  re-running it.
- A convergence that trips on something transient self-heals:
  `common/converge.sh` resumes the run (`gh run rerun --failed` — CI is
  exec-id + `--retry` resume-capable) up to 3 times before failing.

## Prerequisites (once)

1. `orun auth login --device` (approve at app.orun.dev/cli/device).
2. A workspace for the product; note its `ws_…` id.
3. The three integrations connected in that workspace — GitHub,
   Cloudflare, Supabase. Deploy phases (03+) POLL for these up to 10
   minutes, so you can click the consents while preflight waits.

## Shared machinery (`flows/common/`)

| script | role |
|---|---|
| `preflight.sh` | auth → authoritative integrations probe → 10m poll for the three connections → repo allow-list, self-healing via `orun cloud link` |
| `apply-blueprint.sh` | apply one blueprint slice into the product repo, rebrand it (identity from `.rebrand/values.json`), archive phase provenance; enforces a clean tree; `dryrun` shows + reverts |
| `land-pr.sh` | commit → branch → PR → wait for checks (passes when the repo has none yet) → merge (admin bypass when available) → back on main |
| `converge.sh` | wait for the main convergence run; auto-resume through transient failures |
| `verify-endpoints.sh` | probe api-edge `/health` / console URLs, derived from `.rebrand/values.json` |
| `create-secrets.sh` | the five brokered provider secrets; idempotent, self-heals orphans |

## Where the blueprints live

Each phase folder carries its own `blueprint.yaml` — the slice it applies.
They are derived from the baseline's monolithic `repo-blueprint.yaml`
(Lumen as a Blueprint of itself); regenerate them after editing it:

```bash
python3 tooling/blueprint/split-phases.py repo-blueprint.yaml flows/phases
```

The split prunes cross-phase `dependsOn` edges (ordering becomes the run
sequence), keeps hooks on the scaffold phase only, and re-bases each
blueprint's dir source relative to its own folder.

## Relationship to the express flow

The express path is `flows/common/instantiate-all.sh` (applies every phase
blueprint into one tree) followed by `flows/bootstrap-flow.yaml`: full tree
instantiated parked, whole fleet un-parked in a single push, one
convergence run. The phased path builds the repo incrementally — each
phase's merge deploys exactly its slice, no parking involved. Same shared
scripts, same guarantees; pick per product, they end in the same place.
