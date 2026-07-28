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
3. **Repo allow-list** — the workspace must trust this repo's CI identity
   (OIDC). `orun cloud check --org <org>` verifies; granting is done in the
   console (Git Repos) — the CLI cannot grant it. `orun cloud link` must have
   been run from a clone with a GitHub remote (it records the numeric repo id
   the OIDC exchange resolves by).

## The workflow

```bash
orun workflow run flows/bootstrap-flow.yaml --set org=<org>
```

- **preflight** — auth, allow-list, then POLLS for ACTIVE Cloudflare +
  Supabase connections (up to 10m, printing the console URL) so the OAuth
  consents can be granted while the flow runs.
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
  resolve them at claim time. `flows/converge.sh` auto-resumes the run
  through transient failures (`gh run rerun --failed`; CI is
  exec-id + `--retry` resume-capable), budget 3 — a real regression still
  fails every resume and surfaces.
- **restore-bindings** — second (final) push: `cycle-break.mjs --restore`
  puts the stripped service bindings back (every worker they point at now
  exists) and requires that convergence green too.
- **verify-live** — curls the deployed api-edge `/health` + console endpoints
  on both environments and fails on any dead endpoint.

Every step is also runnable by hand (`flows/converge.sh [run-id] [resumes]`,
`flows/create-secrets.sh <org>`, `node flows/park.mjs unpark --all`), and a
failed flow resumes by re-running the workflow — completed steps are no-ops
(the fleet is already un-parked, `cycle-break --strip/--restore` are
idempotent, and secrets self-heal). `flows/batch.sh <name> <components…>`
remains for *incremental* rollouts after the baseline is live (it PRs a batch
and waits for checks + convergence), but the bootstrap itself no longer
batches.

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
