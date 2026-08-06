# BOOTSTRAP — fresh product from this baseline, in phases

How to go from **nothing** to a **fully deployed, documented baseline**
(all terraform infra, the 12-worker fleet, api-edge, the console — live on
stage+prod) with the phased bootstrap workflows plus two OAuth consents.
Proven end-to-end by the `nimbus`, `vela`, and `ambient` instantiations
(the last fully headless with a workspace-scoped token).

Target wall-clock: **under an hour**. The long pole is Supabase project
creation (~5–10 min per environment); the worker fleet itself converges in
minutes.

## 0. What you need

- GitHub org access (repo creation) and a machine with `git`, `gh`, `node`,
  `python3`, and the `orun` CLI ≥ v2.52.6 (same floor as the product lane pin).
- A Cloudflare account (Workers paid plan for the fleet) and its **Account
  API token** (the console's Connect recipe lists the exact permission
  groups).
- A Supabase organization (capacity for `<repo>-stage` / `<repo>-prod`
  projects) whose OAuth consent you can grant.
- An Orun Cloud workspace for the product (`workspace:` in `intent.yaml`),
  with an **admin-role API key** for headless runs (builder/viewer keys can
  read but their secret writes are denied — masked as `not_found`).
- **The repo allow-listed in the workspace** (console → Settings → Git
  repos). This is the ONE console action a workspace-scoped token cannot
  self-heal (`cloud link` is refused for them) — do it up front or the
  first preflight will stop and ask for it. Everything else is headless.

## 1. One command: the umbrella

The whole bootstrap, unattended — phases 01→08 with per-phase retry, an
early credential write-probe, and an independent final verification:

```bash
orun workflow run flows/phases/00-all/workflow.yaml \
  --set workspace=ws_XXXXXXXX --set reponame=acme \
  --set productname="Acme Cloud" --set productdomain=acme.dev \
  --set subdomain=<workers-dev-subdomain>
```

`subdomain` is the Cloudflare **account's** workers.dev subdomain, not the
product name. Every generated URL and the api-edge CORS allowlist derive from
it, so a wrong value ships a product that deploys cleanly and is unreachable at
every address it advertises. Find it under Workers & Pages in the dashboard.

**Resuming a failed run: run the same command again.** The umbrella skips every
phase whose postcondition already holds — from a checkpoint when the workdir
survived, and by probing reality (repo content on `main`, published wiring
secrets, live endpoints) when it did not, so a fresh container resumes just as
well. Two overrides when you want to be explicit:

```bash
--set from=05-edge     # replay from a named phase, ignoring the checkpoint
--set fresh=true       # run every phase again, skipping nothing
```

Retries also stamp `# ci:` redeploy markers on the phase's components. This
matters more than it looks: CI plans `--changed`, so re-applying identical
content after a failed convergence yields an EMPTY plan and never deploys what
the failed attempt left undeployed. Without the markers a partial fleet stays
partial through unlimited restarts.

Headless: same command by remote reference (§2). Details, prerequisites,
and failure semantics: [flows/phases/00-all/README.md](flows/phases/00-all/README.md).

## 1b. Or phase by phase — the same flow, at your pace

`flows/phases/01-scaffold … 08-docs` are eight independent workflows that
take a product from nothing to a live, documented baseline. Each phase is
idempotent (re-running a completed phase is a no-op that re-verifies) and
follows one contract: **apply its slice → land it → watch the convergence
→ verify the outcome**. Full guide: [flows/phases/README.md](flows/phases/README.md),
with a detailed README in every phase folder; every phase supports
`--set dryrun=true`.

```bash
# local mode, from this checkout — phase 01 takes the identity once:
orun workflow run flows/phases/01-scaffold/workflow.yaml \
  --set workspace=ws_XXXXXXXX --set reponame=acme \
  --set productname="Acme Cloud" --set productdomain=acme.dev \
  --set subdomain=<workers-dev-subdomain>

# every later phase reads identity from the product repo:
orun workflow run flows/phases/02-foundation/workflow.yaml \
  --set out=~/sourceplane/acme --set workspace=ws_XXXXXXXX
# … 03 (infra), 04 (workers), 05 (edge), 06 (console), 08 (docs); 07 (domain) optional.
```

What lands in the product is PRODUCT-ONLY: source, infra, CI, configs,
and its own docs. None of this baseline's machinery (flows, rebrand
tooling, agent state, forking docs) ships, and nothing in the product
presents it as a copy of anything.

The workspace needs its three integrations connected once (GitHub,
Cloudflare, Supabase) — preflight polls up to 10 minutes so consents can
be clicked while it waits:

- **Cloudflare**: paste the Account API token (in-console recipe).
- **Supabase**: OAuth consent; pick the organization that owns this
  product's projects. Changing the OAuth app's scopes later revokes every
  existing connection of that app (secrets go `orphaned`; re-connect +
  `flows/common/create-secrets.sh <ws>` self-heals).

Handing the bootstrap to an agent? Use the maintained runbook —
[flows/AGENT-PROMPT.md](flows/AGENT-PROMPT.md) — instead of writing your own.

## 2. Headless / container mode (Daytona, CI, any sandbox)

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
# … phases 03–08 identically, at your pace. Add --set dryrun=true to preview.
# Phase 08 (docs) is the close-out: it records the VERIFIED live state in
# the product repo and is safe to re-run any time as a live-state refresh.
```

| requirement | detail |
|---|---|
| image deps | `git`, `gh`, `node` (≥20), `python3`, `curl`, `orun` ≥ v2.52.6 (the product's ci.yml lane pin matches) |
| `ORUN_TOKEN` | orun access token; preflight authenticates with it (no login flow) |
| `GITHUB_TOKEN` | fine-grained PAT: **read** on `sourceplane/lumen` (baseline fetch); on the PRODUCT repo: **contents write** (pushes), **pull-requests write** (landings), **actions read+write** (converge watches runs and auto-resumes via `gh run rerun`), **checks read**; **repo create** on the org if phase 01 creates the repo (or pre-create it — supported) |
| pinning | the `@<ref>` in the remote reference pins EVERYTHING — the flow fetches its baseline at that exact commit (`ORUN_FLOW_SOURCE_SHA`). Use a tag for reproducible bootstraps; `@main` for latest |
| workdir | phases share `baseline/` and `product/` anchored at the invocation cwd (stable across phases and re-runs — idempotent) |
| classic-token caveat | a CLASSIC PAT or gh OAuth token additionally needs the `workflow` scope to push `.github/workflows/` (hit live); fine-grained PATs need only `contents: write` |
| identity | commits fall back to `bootstrap-bot` when no git identity is configured |

## 3. After the baseline is live

- **Custom domain**: create the product zone in Cloudflare, then run
  [phase 07](flows/phases/07-domain/README.md), and re-run phase 08 so the
  docs pick up the domain URLs.
- **Runtime secrets** (OAuth client secrets, billing keys, …): seed with
  `orun secrets set <KEY> --org <org> --env <env>`; the next deploy pushes
  them to the workers (`wire-now-seed-later` — nothing blocks on them).
- **Incremental rollouts**: normal PRs — merges to `main` converge
  automatically.

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
| Secret WRITE fails `not_found` while listings work | The API key's role is below ADMIN (resource-hiding masks the denial). Re-mint the key with the admin role; `create-secrets.sh` is idempotent. |
| `apply` dies (OCI 503, network) and the RETRY says "working tree is not clean" | Fixed: apply-blueprint self-heals its own crash debris via an inflight marker. On older baselines: `git reset --hard origin/main && git clean -fd` in the product, then re-run. |
| Console/edge smoke fails right after the FIRST deploy of a worker | workers.dev route propagation race — the deploy lane's smoke retries with backoff (stack-tectonic ≥ 0.18.2); a resume (`converge.sh` does 3) clears older pins. |
| Terraform lane: "state already locked" by ITS OWN plan | Backend lock-release race — a convergence resume clears it. |
| Environment cannot observe GitHub Actions (gh 403) | Landings/converge fall back to plain REST automatically (ghrest.sh). If even REST Actions is blocked: `--set watch=false` skips the converge watch — then verify the run out-of-band before the next phase. |
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
