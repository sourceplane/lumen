# Phase 03 — infrastructure

The first phase that **deploys**: lands the data plane
(`flows/phases/03-infrastructure/blueprint.yaml`) and converges it against real
providers. Its terraform outputs are published as job-output secrets that
every later phase consumes.

## What it lands

`infra/terraform/`: `cloudflare-kv`, `supabase`, `db-migrate`,
`cloudflare-hyperdrive` — each with a `terraform` (or `db-migrate`)
component and the self-healing `adopt.tf` import machinery.

The merge's convergence applies them in DAG order:
`supabase → db-migrate → cloudflare-hyperdrive`, with `cloudflare-kv` in
parallel. On success each apply lease-publishes its outputs to the
project/env secret rungs: `SUPABASE_PROJECT_REF`, `SUPABASE_DB_PASSWORD`,
`SUPABASE_DB_URL`, `WIRING_CLOUDFLARE_KV`, `WIRING_CLOUDFLARE_HYPERDRIVE`.

## Prerequisites

All three integrations ACTIVE in the workspace (preflight polls up to 10m
so consents can be clicked while it waits), plus:

- Supabase org capacity for `<repo>-stage` / `<repo>-prod` projects —
  project creation is the phase's long pole (~5–10 min per environment).
- Cloudflare account on the Workers paid plan.

## Inputs

`out`, `workspace`, optional `dryrun` (see [the phases README](../README.md)).

## Steps

1. **preflight** — `common/preflight.sh`: auth, integrations poll,
   allow-list self-heal.
2. **secrets** — `common/create-secrets.sh`: the five brokered provider
   keys (workers-deploy / hyperdrive-edit / account-id /
   management-access / org-id). Idempotent; orphaned keys are recreated
   against the current ACTIVE connection.
3. **apply** → **land** → **converge** — the standard contract, with one
   deliberate difference: the landing merges WITHOUT waiting on PR checks
   (`land-pr.sh --no-wait`). On a fresh product the PR's db-migrate and
   hyperdrive plan lanes are structurally red — they resolve supabase's
   job-output secrets, which only exist once the merge's main run APPLIES
   supabase. The convergence step is the real gate.
4. **verify** — asserts `WIRING_CLOUDFLARE_KV`,
   `WIRING_CLOUDFLARE_HYPERDRIVE`, `SUPABASE_PROJECT_REF` exist on the
   stage env rung. Missing keys mean an apply did not publish — check that
   lane first.

## Failure modes we have actually hit

| symptom | meaning → fix |
|---|---|
| supabase lane: `does not support oauth access` on `/billing/addons` | provider ≥1.6 sneaked in — the root pins `~> 1.5.1`; keep the pin |
| supabase lane: duplicate project name | the org already has `<repo>-<env>`. Same product re-bootstrapping → `adopt.tf` imports it automatically; a stray half-torn-down project → delete it in Supabase |
| kv apply: title already exists (10014) with empty platform state | `adopt.tf` imports by title at plan time — if you removed it, restore it |
| secret resolution: `orphaned` | a provider connection was revoked/replaced — re-connect, then re-run the phase (create-secrets self-heals) |
| verify: WIRING keys missing | the corresponding terraform lane failed or was skipped — `gh run view` the convergence run, fix, re-run the phase |

## Cutover note (re-bootstrapping an EXISTING product)

`random_password` cannot be adopted: when `adopt.tf` imports an existing
Supabase project, the first apply RESETS the database password and
republishes it — every consumer re-wires from the new secrets in the same
run, but anything outside the platform still holding the old credentials
breaks at that moment.

## Example commands

From the baseline checkout (local mode):

```bash
orun workflow run flows/phases/03-infrastructure/workflow.yaml \
  --set out=$HOME/sourceplane/acme --set workspace=ws_ABCD1234
```

Headless (fresh container / no checkout — see BOOTSTRAP.md §3c): same
command by remote reference, with `ORUN_TOKEN` + `GITHUB_TOKEN` exported
and `--set repo=<owner/name>` instead of `out`:

```bash
export ORUN_TOKEN="$(orun auth token | tail -1)" GITHUB_TOKEN=…
orun workflow run github:sourceplane/lumen@main//flows/phases/03-infrastructure/workflow.yaml \
  --set workspace=ws_ABCD1234 --set repo=sourceplane/acme
```

Preview with zero side effects (either mode): append `--set dryrun=true` —
the blueprint is applied, shown, and reverted; nothing is pushed or
deployed. Re-running a completed phase is always safe (idempotent): the
apply is a no-op, the landing finds nothing, and verify re-asserts.

Prerequisite reminder: all three integrations (GitHub, Cloudflare,
Supabase) must be ACTIVE in the workspace — preflight polls up to 10m so
the consents can be clicked while it waits. Check first with:

```bash
orun integrations list ws_ABCD1234
```

## Next

[Phase 04 — workers](../04-workers/README.md).
