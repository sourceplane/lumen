# BOOTSTRAP — fresh product from this baseline, one workflow

How to go from **nothing** to a **fully deployed working baseline** (all
terraform infra, the 12-worker fleet, api-edge, the console — live on
stage+prod) with one workflow run plus two OAuth consents. Proven end-to-end
by the `nimbus` instantiation (2026-07-28); the residual manual reruns it
needed are engineered away (smoke retry, resume dep-grace, single-run flow).

Target wall-clock: **under an hour**. The long pole is Supabase project
creation (~5–10 min per environment); the worker fleet itself converges in
minutes.

## 0. What you need

- GitHub org access (repo creation) and a machine with `git`, `gh`, `node`,
  `python3`, and the `orun` CLI ≥ v2.49.0.
- A Cloudflare account (Workers paid plan for the fleet) and its **Account
  API token** (the console's Connect recipe lists the exact permission
  groups).
- A Supabase organization (capacity for `<repo>-stage` / `<repo>-prod`
  projects) whose OAuth consent you can grant.
- An Orun Cloud workspace for the product (`workspace:` in `intent.yaml`).

## 1. Instantiate the repo from the blueprint

```bash
flows/common/instantiate-all.sh ~/sourceplane/acme \
  --set repoName=acme \
  --set productName="Acme Cloud" \
  --set productDomain=acme.dev \
  --set workersDevSubdomain=<workers-dev-subdomain> \
  --set orunWorkspace=ws_XXXXXXXX
```

Run it from the baseline checkout. It applies every phase blueprint
(`flows/phases/<n>/blueprint.yaml`) into one output tree — the express
alternative to running the phases one at a time.

Rebrand values (`tooling/rebrand/values.example.json`): `repoName`,
`productName`, `productDomain`, and `workersDevSubdomain`. Keeping the
baseline's workers.dev subdomain is fine when the fork shares the Cloudflare
account — worker names are brand-prefixed, and the rebrand sweep accepts a
kept subdomain (it only flags the subdomain when you *changed* it).

The first CI push runs only the offline verify fleet: every deployable
component starts **parked** (`flows/subscriptions/`).

## 2. Link the workspace

```bash
orun auth login --device       # approve at app.orun.dev/cli/device
```

That is all — the workflow's preflight self-heals the repo link/allow-list
(`orun cloud link`, driven by the git remote and the workspace's GitHub
integration) and waits for the provider consents.

## 3. Run the workflow

With a workspace id, an authenticated CLI, and the three integrations
connected (GitHub, Cloudflare, Supabase), this ONE command handles
everything — the repo allow-list self-heals via `orun cloud link`, secrets
are brokered, and the whole fleet deploys in one convergence run:

```bash
orun workflow run flows/bootstrap-flow.yaml --set workspace=<ws-id>
```

`workspace` accepts the workspace id (`ws_…`) or its slug.

To preview everything first without changing anything (no secrets created,
no push, no deploy — reports connection/secret health, shows the exact
unpark+strip diff and reverts it, and probes the endpoints without failing):

```bash
orun workflow run flows/bootstrap-flow.yaml --set workspace=<ws-id> --set dryrun=true
```

Preflight **waits up to 10 minutes** for the two provider connections — grant
them in the console (→ Integrations) while it polls:

- **Cloudflare**: paste the Account API token (in-console recipe).
- **Supabase**: OAuth consent; pick the organization that owns this product's
  projects. Scopes live on the OAuth app itself — changing them later
  **revokes every existing connection of that app across all workspaces**
  (secrets go `orphaned`; re-connect + `flows/common/create-secrets.sh <org>`
  self-heals).

Then the flow runs unattended: brokered secrets → one main push un-parking
the whole fleet (feedback service-bindings stripped) → **one convergence
run** deploying everything in DAG order (supabase → db-migrate + hyperdrive →
workers → api-edge → console), auto-resumed through transient failures → a
final push restoring the service bindings → live-endpoint verification.

`flows/README.md` documents each step and the ordering guarantees;
`ai/context/fork-from-baseline.md` records the fork provenance.

## 3b. Or: bootstrap in phases, at your own pace

Prefer landing the product slice by slice — each with its own PR, deploy,
and verification? `flows/phases/01-scaffold … 07-domain` are seven
independent workflows (phase 01 replaces steps 2–3 above; later phases need
only `--set out=… --set workspace=…`). Full guide:
[flows/phases/README.md](flows/phases/README.md), with a detailed README in
every phase folder. Every phase supports
`--set dryrun=true`.

## 3c. Headless / container mode (Daytona, CI, any sandbox)

Every phase workflow is fully self-contained: reference it remotely, give
it two tokens, and it fetches everything itself — the baseline at the SAME
commit the flow came from, the product repo by name. Nothing to check out,
nothing interactive.

```bash
# The whole container contract:
export ORUN_TOKEN=…          # orun auth, headless
export GITHUB_TOKEN=…        # fine-grained PAT (scopes below)

orun workflow run github:sourceplane/lumen@<ref>//flows/phases/01-scaffold/workflow.yaml \
  --set workspace=ws_… --set reponame=acme --set productname="Acme Cloud" \
  --set productdomain=acme.dev --set subdomain=<workers-dev-subdomain>

orun workflow run github:sourceplane/lumen@<ref>//flows/phases/02-foundation/workflow.yaml \
  --set workspace=ws_… --set repo=sourceplane/acme
# … phases 03–07 identically, at your pace. Add --set dryrun=true to preview.
```

| requirement | detail |
|---|---|
| image deps | `git`, `gh`, `node` (≥20), `python3`, `orun` ≥ v2.52.1 (headless workspace→slug resolution; ≥ v2.50.0 works if `workspace` is passed as a slug) |
| `ORUN_TOKEN` | orun access token; preflight authenticates with it (no login flow) |
| `GITHUB_TOKEN` | fine-grained PAT: **read** on `sourceplane/lumen` (baseline fetch); on the PRODUCT repo: **contents write** (pushes), **pull-requests write** (landings), **actions read+write** (converge watches runs and auto-resumes via `gh run rerun`), **checks read**; **repo create** on the org if phase 01 creates the repo (or pre-create it — supported) |
| pinning | the `@<ref>` in the remote reference pins EVERYTHING — the flow fetches its baseline at that exact commit (`ORUN_FLOW_SOURCE_SHA`). Use a tag for reproducible bootstraps; `@main` for latest |
| workdir | phases share `baseline/` and `product/` anchored at the invocation cwd (stable across phases and re-runs — idempotent) |
| classic-token caveat | a CLASSIC PAT or gh OAuth token additionally needs the `workflow` scope to push `.github/workflows/` (hit live); fine-grained PATs need only `contents: write` |
| identity | commits fall back to `bootstrap-bot` when no git identity is configured |

## 4. After the baseline is live

- **Custom domain**: create the product zone in Cloudflare, then un-park
  `cloudflare-domain` (`node flows/common/park.mjs unpark cloudflare-domain`, PR it —
  or `flows/batch.sh domain cloudflare-domain`).
- **Runtime secrets** (OAuth client secrets, billing keys, …): seed with
  `orun secrets set <KEY> --org <org> --env <env>`; the next deploy pushes
  them to the workers (`wire-now-seed-later` — nothing blocks on them).
- **Incremental rollouts**: normal PRs; `flows/batch.sh` for grouped
  enable-style changes.

## Troubleshooting (everything we hit doing this for real)

| Symptom | Cause → fix |
|---|---|
| Preflight times out on connections | Consent not granted yet — console → Integrations, then re-run the flow (idempotent). |
| Secrets listed `orphaned` | Their connection was revoked/replaced (e.g. OAuth app scopes changed). Re-connect the provider; `flows/common/create-secrets.sh <org>` recreates against the ACTIVE connection. |
| Supabase lane: `does not support oauth access` on `/billing/addons` | Provider ≥ 1.6.0 sneaked in — the roots pin `~> 1.5.1`; keep the pin. |
| Supabase lane: duplicate project name | The org already has `<repo>-<env>` (a half-torn-down previous attempt). Adoption imports it automatically when it's the *same* product re-bootstrapping; otherwise delete the stray project. |
| Terraform: resource already exists (10014 etc.) with empty platform state | `adopt.tf` handles this by importing at plan time — present in kv / hyperdrive / supabase roots. Roots without adoption must be state-migrated or the resource deleted. |
| Convergence run fails, lanes look transient | `flows/common/converge.sh <run-id>` resumes it (`gh run rerun --failed` = true resume: exec-id + `--retry`). The flow already does this ×3. |
| Worker verify lane: missing `WIRING_*` / `SUPABASE_*` secret | Its terraform upstream hasn't applied (check that lane first) — inside one convergence run the DAG guarantees order; across manual partial runs it does not. |
| CLI login dies with 429 `rate_limited` | Fixed ≥ v2.48.1 (redeem honors Retry-After). Upgrade the CLI. |
| Many lanes queued, none claiming | Runner-pool starvation — `max-parallel: 8` in ci.yml is deliberate (resolve-herd); patience, or check the run isn't superseded. |

## Architecture invariants this depends on

- **CI holds one credential: `GITHUB_TOKEN`.** Provider credentials are
  brokered per run from workspace integrations; terraform state lives on the
  platform (`backend "http"`, run-token auth); terraform outputs travel as
  lease-published job-output secrets. No AWS, no Secrets Manager, no
  long-lived provider tokens anywhere.
- **Resume-capable CI**: exec-id is the GitHub run id (no attempt suffix) and
  every lane passes `--retry` — `gh run rerun --failed` is a true resume.
- **Parked-by-default fleet** at instantiation; the bootstrap un-parks it in
  one push. `cloudflare-domain` is the only component parked by design.
