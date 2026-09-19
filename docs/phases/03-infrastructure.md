# Phase 03 — infrastructure (two landings)

The first phase that **deploys**: it lands the data plane and converges it
against real providers — a Supabase Postgres project, a KV namespace, a
Hyperdrive connection pool and the schema migrations, on stage and prod. Its
terraform outputs are published as job-output secrets that every later phase
consumes.

It is two phases in `repo-blueprint.yaml`, landed one after the other and
filed under one milestone:

| phase | places | publishes |
|---|---|---|
| `03-infrastructure` | `supabase`, `cloudflare-kv` | `SUPABASE_PROJECT_REF`, `SUPABASE_DB_PASSWORD`, `SUPABASE_DB_URL`, `WIRING_CLOUDFLARE_KV` |
| `03-infrastructure-database` | `cloudflare-hyperdrive`, `db-migrate` | `WIRING_CLOUDFLARE_HYPERDRIVE` (and the applied schema) |

## Why two landings

Hyperdrive and db-migrate READ the database the first landing creates. Their
lanes resolve `SUPABASE_PROJECT_REF`, `SUPABASE_DB_PASSWORD` and
`SUPABASE_DB_URL` — Hyperdrive to build its origin, db-migrate to connect —
and those three are **job-output secrets of the supabase terraform APPLY**.
An apply runs only on `main`, after a merge. And a job's secret refs are
resolved before its first step whatever its profile does, so a PR lane that
only plans still needs them.

On a fresh product, then, a PR that places all four modules is red by
construction: the Hyperdrive and db-migrate lanes ask for secrets that
cannot exist until that same PR has merged. The shell layer this blueprint
replaced placed all four here anyway and merged the PR without waiting on its
checks, leaving the convergence on `main` as the only gate. That also meant
the phase could never be verified before it merged.

Every phase is now a pull request that is verified, then merged. So the two
consumers move to a follow-on phase that runs once supabase's outputs exist,
and each landing is one whose every lane can be green. It is a second phase
rather than more hooks on the first because `post` hooks all run before
`await` — "land, converge, *then* land the rest" cannot be one phase's hook
list — and because two units of work that land separately, with their own PR
and their own task, are two phases here.

Supabase project creation takes five to seven minutes per environment and
dominates the first landing. Nothing on our side shortens it.

## Prerequisites

The three integrations ACTIVE in the workspace — the phase's
`requires.probe` polls up to 10 minutes, so the consents can be clicked
while it waits:

- **GitHub** — the App installation on `githuborg` (already required by
  `01-scaffold`).
- **Cloudflare** — the account's **Account API token**, on the Workers paid
  plan (the fleet needs it). Three keys are minted from it, and a minted
  child can never exceed its parent, so its permission groups must cover
  both deploy templates: `workers-deploy` needs Workers Scripts Write,
  Workers KV Storage Write and Account Settings Read; `hyperdrive-edit`
  needs Hyperdrive Write and Account Settings Read. A token without them
  gets its mint refused as `parent_grant_insufficient`.
- **Supabase** — the OAuth consent, picking the organization that will own
  `<reponame>-stage` and `<reponame>-prod`; a pasted personal access token
  (`sbp_…`) works too. The connection is anchored on ONE organization, and
  `SUPABASE_ORG_ID` is that organization's id — both projects are created
  there, so it needs capacity for two more. For an account in several
  organizations, the OAuth consent, where you pick one, is the way to be
  sure which.

Check first with:

```bash
orun integrations list --org ws_ABCD1234 --json
```

## `03-infrastructure`

### What it lands

- `infra/terraform/supabase` — a Supabase project per environment,
  `<reponame>-<env>`, in the component's `supabaseRegion`
  (`ap-southeast-1` in this baseline), with a database password terraform
  generates. The provider is pinned `~> 1.5.1` (see failure modes).
- `infra/terraform/cloudflare-kv` — api-edge's idempotency namespace per
  environment.

Both roots carry the self-healing `adopt.tf` import machinery. The merge's
convergence applies them in parallel, and on success each apply
lease-publishes its outputs to the project's **environment** rungs (stage and
prod), not to the workspace: supabase publishes `SUPABASE_PROJECT_REF`,
`SUPABASE_DB_PASSWORD`, `SUPABASE_DB_URL`; kv publishes `WIRING_CLOUDFLARE_KV`.

### Steps

1. **requires** — `02-foundation` placed, and a `requires.probe`:
   `orun.doctor/check@v1` for `github`, `cloudflare` and `supabase`, with
   `githubOwner`, up to 10 minutes. A declared precondition, not a
   preamble: a consent nobody has clicked is a *wait*, and the phase says so
   rather than failing.
2. **pre** — the phase's task, then five `orun.integrations/reconcile@v1`
   hooks, one per scope template:

   | key | provider | template | read by |
   |---|---|---|---|
   | `CLOUDFLARE_API_TOKEN` | cloudflare | `workers-deploy` | kv, every worker deploy |
   | `CLOUDFLARE_HYPERDRIVE_TOKEN` | cloudflare | `hyperdrive-edit` | hyperdrive (next phase) |
   | `CLOUDFLARE_ACCOUNT_ID` | cloudflare | `account-id` | the Cloudflare lanes — a connection fact, not a secret |
   | `SUPABASE_ACCESS_TOKEN` | supabase | `management-access` | supabase, db-migrate |
   | `SUPABASE_ORG_ID` | supabase | `org-id` | supabase — a connection fact, not a secret |

   One hook per template because each mints from ONE connection with ONE
   scope, and these are five scopes on purpose: the deploy token
   deliberately cannot touch Hyperdrive. A reconcile, not a create: keys
   that exist are KEPT, and missing or orphaned keys are minted against the
   current ACTIVE connection. None holds a value — a brokered secret is a
   pointer at a connection and a scope template, minted just-in-time at
   resolve. `CLOUDFLARE_HYPERDRIVE_TOKEN` is minted here although nothing
   reads it until the next phase: this is the phase that asks for the
   connections, and a key minted with its siblings is one the console card
   lists in one place.
3. **place** → **brand** → **lockfile** → **land** — the standard contract
   (PR `phase(03-infrastructure): supabase, kv`). The PR's terraform plan
   lanes resolve the minted keys over remote state; the landing merges only
   on green.
4. **converge** — `orun.run/watch@v1` on the merged commit; this is where
   the Supabase projects are created.
5. **verify** — `orun.secrets/exists@v1` asserts `WIRING_CLOUDFLARE_KV`,
   `SUPABASE_PROJECT_REF`, `SUPABASE_DB_PASSWORD` and `SUPABASE_DB_URL` on
   the project's **stage and prod** environments. The shell layer checked
   stage only, and a prod apply that failed passed it. A missing key is
   named per environment and means that environment's apply did not
   publish — read that lane first.

## The second landing: `03-infrastructure-database`

### What it lands

- `infra/terraform/cloudflare-hyperdrive` — a Hyperdrive config per
  environment, pooling connections to that environment's Supabase database.
  It binds `CLOUDFLARE_HYPERDRIVE_TOKEN` as its `CLOUDFLARE_API_TOKEN`,
  because the deploy token cannot touch Hyperdrive, and reads the project
  ref and database password from supabase's outputs.
- `infra/db-migrate` — the migration runner, applying the schema in
  `packages/db/src/migrations` to stage and prod. It plans on the PR and
  applies after the merge.

On success Hyperdrive publishes `WIRING_CLOUDFLARE_HYPERDRIVE` to both
environment rungs; the workers render their Hyperdrive binding from it.

### Steps

1. **requires** — `03-infrastructure` placed, and a `requires.probe`:
   `orun.secrets/exists@v1` for `SUPABASE_PROJECT_REF`,
   `SUPABASE_DB_PASSWORD` and `SUPABASE_DB_URL` on stage and prod. This is
   the question the split exists to ask: do the outputs these lanes read
   exist yet?
2. **pre** — the task, filed under the `03-infrastructure` milestone.
3. **place** → **brand** → **lockfile** → **land** — PR
   `phase(03-infrastructure): hyperdrive, db-migrate`. Its plan lanes now
   resolve supabase's outputs on the PR, so it can be green before it
   merges.
4. **converge** — migrations apply and Hyperdrive is created on both
   environments.
5. **verify** — `orun.secrets/exists@v1` asserts
   `WIRING_CLOUDFLARE_HYPERDRIVE` on stage and prod. `04-workers` asks the
   same question, with `WIRING_CLOUDFLARE_KV`, as its own `requires.probe`,
   so it will not start on a half-applied phase 03.

## Failure modes

Most of these were hit on real Lumen bootstraps; the rest are the
questions the split and the reconcile now ask up front.

| symptom | meaning → fix |
|---|---|
| `03-infrastructure` waits on connections, then stops | a consent is not granted yet — console → Integrations, then re-run the phase |
| reconcile refused: `parent_grant_insufficient` | the Cloudflare token's permission groups do not cover a template (Hyperdrive Write is the usual gap) — re-issue the token with them, re-connect, re-run the phase |
| supabase lane: `does not support oauth access` on `/billing/addons` | provider ≥ 1.6 sneaked in; from 1.6.0 it reads a billing endpoint Supabase does not serve to OAuth tokens — the root pins `~> 1.5.1`; keep the pin |
| supabase lane: duplicate project name | the organization already has `<reponame>-<env>`. The same product re-bootstrapping → `adopt.tf` imports it automatically; a stray half-torn-down project → delete it in Supabase |
| kv, hyperdrive or supabase apply: resource already exists (10014 for a KV title, etc.) with empty platform state | `adopt.tf` imports by name at plan time — present in the kv, hyperdrive and supabase roots; if you removed it, restore it |
| `03-infrastructure-database` refuses: `SUPABASE_*` missing on an environment | that environment's supabase apply did not publish — read its lane in `03-infrastructure`'s convergence, fix, re-run `03-infrastructure` |
| db-migrate: missing `SUPABASE_*` secrets | the supabase lane has not applied for that environment — check it first |
| a migration fails | fix forward with a new migration; never edit an applied one |
| secret resolution: `orphaned` | a provider connection was revoked or replaced — changing the Supabase OAuth app's scopes revokes every connection of that app. Re-connect, then re-run `03-infrastructure`; the reconcile re-mints only what is missing |
| secret WRITE fails `not_found` while listings work | the API key's role is below ADMIN (resource-hiding masks the denial) — re-mint the key as admin; the reconcile is idempotent |
| verify: `WIRING_*` or `SUPABASE_*` keys missing | the corresponding terraform lane failed or was skipped — `gh run view` the convergence run, fix, re-run the phase |

## Re-bootstrapping an EXISTING product

Adoption makes both landings safe to repeat against resources that already
exist: the Supabase project, the KV namespace and the Hyperdrive config are
imported at plan time rather than colliding.

One cutover caveat, and it is real: `random_password` cannot be adopted.
When `adopt.tf` imports an existing Supabase project, the first apply
**resets the database password** and republishes it. db-migrate, Hyperdrive
and the worker fleet re-wire from the new secrets in the same convergence,
but anything outside the platform still holding the old credentials breaks
at that moment.

## Example commands

From the baseline checkout:

```bash
orun new --blueprint repo-blueprint.yaml --out $HOME/sourceplane/acme \
  --run-hooks --phase 03-infrastructure \
  --values $HOME/sourceplane/acme/.rebrand/values.json

orun new --blueprint repo-blueprint.yaml --out $HOME/sourceplane/acme \
  --run-hooks --phase 03-infrastructure-database \
  --values $HOME/sourceplane/acme/.rebrand/values.json
```

Headless (fresh container / no checkout — see BOOTSTRAP.md §2): clone the
baseline at a tag and run the same commands, with `ORUN_TOKEN` +
`GITHUB_TOKEN` exported:

```bash
export ORUN_TOKEN="$(orun auth token | tail -1)" GITHUB_TOKEN=…
git clone --depth 1 --branch <baseline-tag> https://github.com/sourceplane/lumen
cd lumen
orun new --blueprint repo-blueprint.yaml --out /work/acme \
  --run-hooks --phase 03-infrastructure --values /work/acme.values.yaml
orun new --blueprint repo-blueprint.yaml --out /work/acme \
  --run-hooks --phase 03-infrastructure-database --values /work/acme.values.yaml
```

Preview with zero side effects: drop `--run-hooks` — the phase places files
and stops, with no landing, no convergence watch and no probe. `--status`
derives every phase's state and writes nothing at all. Re-running a
completed phase is safe: the placement is a no-op, the reconcile keeps every
key, the landing finds nothing new, and the `await` hooks re-assert.

## Next

[Phase 04 — workers](04-workers.md).
