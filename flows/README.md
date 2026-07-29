# Bootstrapping this product

This product boots **entirely against its Orun Cloud workspace** (the
`workspace:` in `intent.yaml`; a fork carries provenance in
`.orun/provenance.*.lock` and `ai/context/fork-from-baseline.md`) — CI holds
no provider credential; every secret is brokered from the workspace's
integrations at run time, and Terraform state lives on the platform
(`backend "http"`). There is no AWS anywhere in the loop. Every command below
takes the workspace org slug; the examples write `<org>`.

The full operator runbook (fresh product from the blueprint → live baseline)
is [BOOTSTRAP.md](../BOOTSTRAP.md); this file documents the flow itself.

## One-time operator prerequisites

The workflow preflights each of these; the two console steps can be clicked
*while the flow runs* — preflight polls for up to 10 minutes:

1. **CLI login** — `orun auth login --device`, approve the code at
   `https://app.orun.dev/cli/device` in a browser session that belongs to the
   workspace owner. (When the operator is an agent, the Claude Chrome
   extension can fill and submit the approval form — the CLI itself cannot.)
2. **Integrations** — connect **Cloudflare** (paste an Account API token per
   the in-console recipe; the same account may already back other workspaces
   — that is supported) and **Supabase** (OAuth; pick the organization that
   should own this product's projects) in the console → Integrations.
3. **Repo allow-list** — handled by preflight itself: when `orun cloud
   check` fails it runs `orun cloud link` (git remote + the workspace's
   GitHub integration) and re-checks. Only if that still fails does the
   console (Git Repos) need a manual grant.

## The workflow

```bash
orun workflow run flows/bootstrap-flow.yaml --set workspace=<ws-id>
```

Add `--set dryrun=true` to preview the whole flow with zero side effects:
secret actions are reported instead of executed, the unpark/strip diff is
shown and reverted (nothing pushed), converge only reports the latest main
run, and verify-live reports endpoint codes without failing the step.
`orun workflow validate flows/bootstrap-flow.yaml` checks the file itself;
`orun workflow view` renders the DAG.

- **preflight** — auth; POLLS for ACTIVE GitHub + Cloudflare + Supabase
  connections (up to 10m) so consents can be granted while the flow runs;
  then the repo allow-list, self-healing via `orun cloud link` when missing.
- **create-secrets** — five project-rung secrets from the integrations
  (workers-deploy / hyperdrive-edit / account-id / management-access /
  org-id). Brokered and fact templates only: no value is ever typed or seen.
  Idempotent and self-healing: a key whose integration connection was revoked
  (health `orphaned`) is revoked and recreated against the current ACTIVE
  connection.
- **deploy-all** — ONE main push: `park.mjs unpark --all` restores every
  deployable component's environment subscriptions (`cloudflare-domain` stays
  parked until the product zone exists in the Cloudflare account), and
  `tooling/bootstrap/cycle-break.mjs --strip` removes the service-binding
  feedback edges so first-boot workers deploy in DAG order without
  referencing not-yet-existing services.
- **converge** — waits for that push's main convergence run: the platform DAG
  orders supabase → db-migrate/cloudflare-hyperdrive → the worker fleet →
  api-edge → web-console-next inside the ONE run; terraform applies
  lease-publish their outputs (`SUPABASE_*`, `WIRING_*`) and downstream lanes
  resolve them at claim time. `flows/common/converge.sh` auto-resumes the run
  through transient failures (`gh run rerun --failed`; CI is
  exec-id + `--retry` resume-capable), budget 3 — a real regression still
  fails every resume and surfaces.
- **restore-bindings** — second (final) push: `cycle-break.mjs --restore`
  puts the stripped service bindings back (every worker they point at now
  exists) and requires that convergence green too.
- **verify-live** — curls the deployed api-edge `/health` + console endpoints
  on both environments and fails on any dead endpoint.

Every step is also runnable by hand (`flows/common/converge.sh [run-id] [resumes]`,
`flows/common/create-secrets.sh <org>`, `node flows/common/park.mjs unpark --all`), and a
failed flow resumes by re-running the workflow — completed steps are no-ops
(the fleet is already un-parked, `cycle-break --strip/--restore` are
idempotent, and secrets self-heal). `flows/batch.sh <name> <components…>`
remains for *incremental* rollouts after the baseline is live (it PRs a batch
and waits for checks + convergence), but the bootstrap itself no longer
batches.

## Phased bootstrap — at your own pace

The same journey, split into seven independent workflows under
`flows/phases/` — full guide in [flows/phases/README.md](phases/README.md),
with a detailed README in every phase folder — each self-contained: **apply its blueprint slice → land it
as a PR → watch the deployment convergence (auto-resumed) → verify**. Run
one phase today and the next whenever — every phase is idempotent and
re-runnable, and all of them share `flows/common/`.

All phase workflows run FROM THE BASELINE checkout. Phase 01 takes the
identity inputs and writes them into the product repo
(`.rebrand/values.json`); every later phase needs only `out` + `workspace`
(+ optional `dryrun=true` to preview without changing anything):

| # | workflow | blueprint | lands / verifies |
|---|---|---|---|
| 01 | `phases/01-scaffold` | 07-workspace | repo born + pushed + linked (intent, CI, flows, tooling) |
| 02 | `phases/02-foundation` | 01-foundation | 13 shared packages; verify lanes green |
| 03 | `phases/03-infrastructure` | 02-infrastructure | kv, supabase, db-migrate, hyperdrive; asserts published `WIRING_*`/`SUPABASE_*` |
| 04 | `phases/04-workers` | 03-workers | 12 workers (feedback edges stripped, then restored — two landings) |
| 05 | `phases/05-edge` | 04-edge | api-edge; `/health` live on stage+prod |
| 06 | `phases/06-console` | 05-console | web console; console + edge live |
| 07 | `phases/07-domain` | 06-domain | OPTIONAL — custom domain (zone must exist first) |

```bash
orun workflow run flows/phases/01-scaffold/workflow.yaml \
  --set out=$HOME/sourceplane/acme --set workspace=ws_… \
  --set reponame=acme --set productname="Acme Cloud" \
  --set productdomain=acme.dev --set subdomain=<workers-dev-subdomain>

orun workflow run flows/phases/02-foundation/workflow.yaml \
  --set out=$HOME/sourceplane/acme --set workspace=ws_…
# … and so on, at your pace.
```

Express vs phased: the single `bootstrap-flow.yaml` (above) instantiates the
full tree parked and deploys everything in ONE convergence run; the phased
path builds the repo incrementally — each phase's merge deploys exactly that
slice, no parking involved. Same scripts, same guarantees.

## First-boot ordering guarantees (why one run works)

- Terraform lanes publish their consumable outputs as **job-output secrets**
  (lease-bound, published by the runner on job success) — no separate sync
  step, no ordering gap: a downstream lane's `secretEnv` resolves at claim
  time, after its dependency completed inside the same run.
- Adoption (`infra/terraform/*/terraform/adopt.tf`): when the platform state
  is empty but the provider already has the resource (a baseline predating
  the platform backend, or a recovered workspace), the plan imports it
  instead of colliding — fresh products create normally.
- The smoke step retries with backoff (stack-tectonic ≥ 0.18.1), riding out
  first-deploy workers.dev propagation.
- `--retry` lanes wait for their upstreams' retry claims during a resume
  (orun ≥ v2.49.0) instead of dying on the resume race.

## Runtime worker secrets (wire-now-seed-later)

Workers declare their runtime keys in `optionalSecretEnv` + `runtimeSecrets`
(OAuth client secrets, Polar keys, `SECRET_ENCRYPTION_KEY`, …). They are
**inert until seeded**: add a value in the console (Secrets → New secret) or
via `orun secrets set <KEY> --org <org> --env <env>` and the next deploy pushes
it to the worker via the stack's `secrets-live` step. No repo change per
secret.
