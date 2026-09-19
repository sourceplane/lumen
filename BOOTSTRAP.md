# BOOTSTRAP — fresh product from this baseline, in phases

How to go from **nothing** to a **fully deployed, documented baseline** —
the Supabase and Cloudflare data plane, the 12-worker fleet, api-edge, the
console, live on stage and prod — with two provider consents (Cloudflare and
Supabase) and the GitHub App.

There is one artifact: **`repo-blueprint.yaml`**. It declares what to place,
in what order, what each phase needs first, and what to say while it runs.
`orun new` is the whole runtime — the phases below are its `--phase` names,
not separate workflows. Everything the old shell layer ("the flows") did is
now either a typed action inside the orun binary or a hook this repo still
owns, which is why the version floor matters and why a phase can be run
alone, months later, from a fresh container.

Target wall-clock: **60–75 minutes**. The long poles are the worker fleet
(~31m across its two landings) and the console build (~16m); Supabase
project creation (5–7m per environment) is the longest wait nobody can
shorten. Where the numbers come from, and which are still estimates:
[docs/phases/TIMINGS.md](docs/phases/TIMINGS.md).

## 0. What you need

- **Tools.** `git`, `gh`, `node` (≥ 20), `pnpm`, `python3`, `curl`, and the
  `orun` CLI **≥ v2.58.11**. That is the floor for RUNNING the bootstrap; the
  product's own `ci.yml` lane pin is a separate, lower floor (v2.56.2).
  v2.56.0 carried the phase overlay (before it there is no `--phase` and
  `hooks.{pre,post,await}` does not parse); v2.56.2 let a branded phase
  satisfy the next one's requirement; v2.58.4 resolves a milestone name and a
  rendered bool; v2.58.5 is the first that can bootstrap at all — it writes
  each phase's files on that phase's turn, its landing commits, seeds an
  empty repository and deletes the branch it merged, and a convergence
  watches the commit it landed (`sha:`); v2.58.6 is the first whose landing
  waits for a PR's whole CI run — every phase here is a pull request that
  must go green before it merges; v2.58.7 checks that the workspace's GitHub
  connection is to the account that owns the repository (`githubOwner`),
  without which no PR is ever seen by the platform; v2.58.8 looks for the
  published secrets on the project's environments, where the infrastructure
  publishes them (`secrets/exists` `environments`); v2.58.10 treats a project
  the bootstrap has not created yet as "not yet" rather than a failed
  preflight, without which every fresh build stops before its first phase;
  and v2.58.11 fills `orunWorkspace` from the workspace the build runs in
  (`from: workspace`), which is the only way a console build has of saying
  it. `baseline.yml`'s `blueprint-parses` job pins the same version, so the
  floor is tested rather than remembered.
- **GitHub.** Access to the org or user the product repo will live under
  (`githuborg`), and the Orun GitHub App installed there and connected to the
  workspace. `01-scaffold` waits for that connection to be to the account
  that owns the repo: the platform sees a product's pull requests only
  through it.
- **Cloudflare.** An account on the Workers paid plan (the fleet needs it)
  and its **Account API token** — the console's Connect recipe lists the
  permission groups. Three secrets are minted from it and a minted child can
  never exceed its parent, so the token must cover Workers Scripts Write,
  Workers KV Storage Write, **Hyperdrive Write** and Account Settings Read.
- **Supabase.** An organization with room for two more projects
  (`<reponame>-stage` and `<reponame>-prod`), connected by OAuth consent —
  or by a pasted personal access token. The connection is anchored on ONE
  organization, and that is where both projects are created: for an account
  in several organizations, the OAuth consent, where you pick one, is the way
  to be sure which.
- **An Orun Cloud workspace** for the product — `orunWorkspace`, or the
  workspace the build runs in (ORUN_WORKSPACE) when that is unset — with an
  **admin-role API key** for headless runs. Builder and viewer keys can read,
  but their secret writes are denied (masked as `not_found`), and the first
  write is `03-infrastructure`'s: a sub-admin key gets through two phases
  and stops at the third.
- **The repo linked to the workspace.** `01-scaffold` tries `orun cloud link`
  and then gates on `orun cloud check`. With a user session the link heals
  itself; a workspace-scoped key cannot write links, so the repo must be
  allow-listed in the console (Settings → Git repos) — do it up front, or
  the phase stops and names this step. Everything else is headless.

## 1. One command: `--resume`

The whole bootstrap, unattended. `--resume` places every phase not already
derived as done, in dependency order, honouring each phase's barrier:

```bash
git clone --depth 1 --branch <baseline-tag> https://github.com/sourceplane/lumen
cd lumen

orun new --blueprint repo-blueprint.yaml \
  --out ~/sourceplane/acme --run-hooks --resume \
  --set reponame=acme --set productname="Acme Cloud" \
  --set productdomain=acme.dev --set githuborg=sourceplane \
  --set orunWorkspace=ws_XXXXXXXX \
  --set subdomain=<workers-dev-subdomain>
```

`subdomain` is the Cloudflare **account's** workers.dev subdomain, not the
product name. Every generated URL and the api-edge CORS allowlist derive from
it, so a wrong value ships a product that deploys cleanly and is unreachable
at every address it advertises. Find it under Workers & Pages in the
dashboard.

**`--run-hooks` is the difference between placing files and bootstrapping a
product.** Without it `orun new` writes the tree and stops: no repo is
created, nothing is landed, no convergence is watched, and no phase probes
its preconditions. That is deliberate — it is what makes a dry instantiation
of this baseline possible in CI with no workspace and no provider.

`--resume` is safe to re-run from anywhere, including a fresh container with
a fresh `--out`: **phase state is derived from the tree, never stored.** A
phase whose files are all present but differ from the blueprint — which is
every phase after `01-scaffold` brands the tree — derives as `drifted`, and
`--resume` leaves it placed rather than reverting your product's identity to
`lumen`.

## 1b. Or phase by phase — the same document, at your pace

The phases are `01-scaffold`, `02-foundation`, `03-infrastructure`,
`03-infrastructure-database`, `04-workers`, `04-workers-restore`, `05-edge`,
`06-console`, `07-domain` (only when `domain=true`), `08-docs` — ten phases
filed under eight milestones. Each is idempotent, each follows one contract —
**place its modules → land them as a PR that must go green → watch the
convergence → verify the outcome** — and each carries its own narration.
Full guide: [docs/phases/README.md](docs/phases/README.md), with a page per
phase in that folder.

```bash
# phase 01 takes the identity once:
orun new --blueprint repo-blueprint.yaml --out ~/sourceplane/acme --run-hooks \
  --phase 01-scaffold \
  --set reponame=acme --set productname="Acme Cloud" \
  --set productdomain=acme.dev --set githuborg=sourceplane \
  --set orunWorkspace=ws_XXXXXXXX --set subdomain=<workers-dev-subdomain>

# 01 committed the answers as .rebrand/values.json, keyed by the blueprint's
# own inputs. The required inputs are still validated on every invocation,
# so that file is the easiest --values for every later phase:
orun new --blueprint repo-blueprint.yaml --out ~/sourceplane/acme --run-hooks \
  --phase 02-foundation --values ~/sourceplane/acme/.rebrand/values.json
# … 03-infrastructure, 03-infrastructure-database, 04-workers,
#   04-workers-restore, 05-edge, 06-console, 08-docs;
#   07-domain only with --set domain=true.
```

The flags that shape a run:

| flag | what it does |
|---|---|
| `--status` | derives and prints every phase's state and writes nothing. This is the preview — it parses the document, validates each hook against the action registry, compiles every `when` and every narration template, and does **not** probe. It needs no credential and no network |
| `--phase <name>` | places exactly that phase. Its `requires.phases` still gates: a predecessor that is `pending` refuses the run and names it |
| `--until <name>` | places every phase through that one and stops |
| `--resume` | places every phase not already derived as done |
| `--values <file>` / `--set k=v` | inputs; `--set` overrides the file |
| `--run-hooks` | runs the hooks — probes, secrets, landings, watches. Without it, placement only |

What lands in the product is PRODUCT-ONLY: source, infra, CI, configs, and
its own docs. None of this baseline's machinery ships — not the blueprint or
the card, not the rebrand, bootstrap, fork or migration tooling, not
`tasks/`, `hooks/`, `testing/`, `specs/`, `agents/`, `docs/phases/` or this
file, and only two files of `ai/context/` (`deployment.md`, `operations.md`).
Nothing in the product presents it as a copy of anything. That promise is a
test: `testing/leak.test.sh` derives what every phase *would* place and gates
the set.

The workspace needs its three integrations connected once. `01-scaffold`
waits for GitHub; `03-infrastructure`'s `requires.probe` polls for all three
for up to 10 minutes, so the consents can be clicked while it waits:

- **Cloudflare**: paste the Account API token (in-console recipe). If its
  permission groups miss one a template needs — Hyperdrive Write is the
  usual gap — that mint is refused (`parent_grant_insufficient`) and
  `03-infrastructure` stops with the message. Re-issue the token, re-connect,
  re-run the phase.
- **Supabase**: OAuth consent; pick the organization that owns this
  product's projects. Changing the OAuth app's scopes later revokes every
  existing connection of that app — the brokered secrets go `orphaned`;
  re-connect and re-run `03-infrastructure`.

`03-infrastructure`'s five secret hooks are a *reconcile*: keys that exist
are kept, keys that are missing are minted against the ACTIVE connection.

| key | provider | template |
|---|---|---|
| `CLOUDFLARE_API_TOKEN` | cloudflare | `workers-deploy` |
| `CLOUDFLARE_HYPERDRIVE_TOKEN` | cloudflare | `hyperdrive-edit` — the deploy token deliberately cannot touch Hyperdrive |
| `CLOUDFLARE_ACCOUNT_ID` | cloudflare | `account-id` — a connection fact, not a secret |
| `SUPABASE_ACCESS_TOKEN` | supabase | `management-access` |
| `SUPABASE_ORG_ID` | supabase | `org-id` — a connection fact, not a secret |

## 2. Headless / container mode (Daytona, CI, any sandbox)

The blueprint's source is this repo itself (`sources: [{kind: dir, path: .}]`),
so the container contract is a shallow clone at a pinned tag plus two tokens.
orun pins the checkout by digest into its object store before any module
reads it, so the run is reproducible and provenanced.

```bash
# The whole container contract:
export ORUN_TOKEN=…          # orun auth, headless
export GITHUB_TOKEN=…        # fine-grained PAT (scopes below)

git clone --depth 1 --branch <baseline-tag> https://github.com/sourceplane/lumen
cd lumen

orun new --blueprint repo-blueprint.yaml \
  --out /work/acme --run-hooks --resume --progress json \
  --values /work/acme.values.yaml
```

`--progress` is four renderings of ONE stream — they differ in what they
show, never in what happened. `json` emits the raw event objects, one JSON
object per line, `schema: bootstrap-event/v1` (a hosted runner or a console
build page reads these); `plain` prints the narration alone, one line per
event, for a CI log; `verbose` adds every detail line; `auto` is narration
with the engine's facts under it.

**The stream is hook execution, not placement.** A run WITHOUT `--run-hooks`
emits one `skipped` event per declared-but-unplaced phase and nothing else —
so `--resume --progress json` with hooks off, which places every phase and
skips none, prints no events at all. That is not a broken flag: the events
describe phases starting, waiting, finishing and failing, and with hooks off
none of that happens. To see the *shape* without a real run, use `--status`.

| requirement | detail |
|---|---|
| image deps | `git`, `gh`, `node` (≥ 20), `pnpm`, `python3`, `curl`, `orun` ≥ v2.58.11 to run the bootstrap. The product's `ci.yml` lane pin (v2.56.2) is its own floor |
| `ORUN_TOKEN` | orun access token; the typed actions authenticate with it (no login flow). A session token from `orun auth token` lives ~30m, shorter than a full run: use the workspace's admin-role API key, mint one per phase, or point `ORUN_TOKEN_FILE` at a file something keeps fresh (the CLI re-reads it on every call and prefers it) |
| `GITHUB_TOKEN` | fine-grained PAT: **read** on `sourceplane/lumen` (the clone); on the PRODUCT repo: **contents write** (pushes), **pull-requests write** (landings), **actions read+write** (`orun.run/watch@v1` watches runs and re-runs failed lanes), **checks read**; **repo create** on the org if `01-scaffold` creates the repo (or pre-create it, empty — supported) |
| pinning | the clone's `--branch <tag>` pins EVERYTHING: the blueprint, its modules, and the hooks' scripts all come from that one commit. Use a tag for reproducible bootstraps; `main` for latest |
| workdir | `--out` is the product tree and is stable across phases and re-runs. The baseline checkout is `{{ .baseline.dir }}` to every hook |
| classic-token caveat | a CLASSIC PAT or gh OAuth token additionally needs the `workflow` scope to push the CI files under `.github` (hit live); fine-grained PATs need only `contents: write` |
| identity | commits fall back to `bootstrap-bot` when no git identity is configured |

> **Contract change.** Earlier Lumen baselines were bootstrapped from a shell
> layer: one workflow file per phase, run by remote reference, and one more
> that ran them all. There are no per-phase files any more: one pinned
> artifact, selected with `--phase <name>`. What the old inputs became:
>
> | then | now |
> |---|---|
> | `workspace` | `orunWorkspace` (or the workspace the build runs in) |
> | `out` / `repo` | `--out` / `githuborg` + `reponame` |
> | `githuborg` defaulting to `sourceplane` | `githuborg` REQUIRED, no default |
> | `epicslug` | `epicSlug` |
> | `dryrun=true` | drop `--run-hooks`, or `--status` |
> | `from`, `fresh` | `--resume`, `--phase`, `--until` |
> | `track` | gone — every landing is tracked |
> | `watch=false` | gone — the watch falls back to REST on its own, and reports rather than hangs if even that is blocked |

## 3. The console path

The console renders **`blueprint.yaml`**, the card, and never this file or
the blueprint directly. The card owns the build contract: the overview, the
three integrations and the admin key role it requires, the inputs the form
collects, a read-only preview of the five brokered secrets and of the
programme (the epic and its eight milestones), and `bootstrap.blueprint:
repo-blueprint.yaml` — the document a runner places. The registry row in
orun-cloud owns identity and the pinned tag; the card is fetched *at* that
tag, which is why it carries none.

What that means for a console build:

- `reponame` and `githuborg` come from the repository the operator picked;
  `apibaseurl` is derived (`https://api.{productdomain}`); only
  `productname`, `productdomain` and `subdomain` are typed.
- `orunWorkspace` is not on the form — it cannot be. The build runs inside
  the workspace, and `from: workspace` (orun ≥ v2.58.11) fills it from there.
- The card collects no `domain`, so a console build skips `07-domain`. Run
  it later from the CLI (and read its page first).
- The runner hands its refreshed token over through `ORUN_TOKEN_FILE`
  (`bootstrap.tokenChannel`), so a session that rotates mid-build does not
  end it.

`testing/manifest.test.sh` holds the card to the blueprint rather than to a
copy of itself: the secrets it previews are compared to the reconcile hooks
that mint them, and its programme and inputs to the blueprint's.

## 4. After the baseline is live

- **Deployment record**: `08-docs` is the close-out, and safe to re-run any
  time as a live-state refresh.
- **Custom domain**: `07-domain` needs the product zone to exist in
  Cloudflare, and in this baseline the `cloudflare-domain` component ships
  parked and mid-migration to provider v5, so the phase lands it without
  deploying anything. See [docs/phases/07-domain.md](docs/phases/07-domain.md)
  before running it.
- **Runtime secrets** (OAuth client secrets, billing keys, …): seed with
  `orun secrets set <KEY> --org <org> --env <env>`; the next deploy pushes
  them to the workers (`wire-now-seed-later` — nothing blocks on them).
- **Incremental rollouts**: normal PRs — merges to `main` converge
  automatically.

## 5. Changing this baseline (maintainers)

This repository's own CI is **`baseline.yml`**, and it never ships: the
blueprint's `ignore` list keeps it out of the `.github` copy, and
`testing/coverage.test.sh` fails on any workflow that reads `testing/`
without being listed there. `ci.yml` is the product's — `plan` and `run`,
the orun component lanes — and every product gets it.

| job | what it proves |
|---|---|
| `baseline-contract` | bash + python3 + PyYAML only: `testing/manifest.test.sh` (card ↔ blueprint), `phases.test.sh` (the partition, the order, the narration, and `docs/phases/` — every phase has a page and every page a phase), `coverage.test.sh` (every component placed by exactly one phase; the ignore list honest), `rebrand.test.sh` |
| `blueprint-parses` | orun pinned at the bootstrap floor, v2.58.11: `orun new --status` reads the document the way a bootstrap will; then `testing/leak.test.sh` (what a product carries) and `testing/placement.test.sh` (the tree placed offline from `tests/fixtures/acme.json`, branded, and made to answer, phase by phase through a rebrand) |

All of it runs locally with no credential and no network — `bash
testing/<name>.test.sh` from the repo root. Leak and placement need `orun` on
`PATH` at the floor version, and placement needs `node` as well.

### What Lumen does not have yet

Cirrus, this baseline's Cloudflare-only sibling, has three things Lumen has
not ported, and their absence is worth stating rather than leaving implied:

- **No tier-3 rehearsal.** Nothing here bootstraps a whole product from
  nothing on a schedule (Cirrus: `testing/rehearsal/`, `rehearsal.yml`). The
  highest tier Lumen's CI reaches is placement, offline.
- **No tag gate.** A `baseline-v*` tag is cut by hand; nothing refuses one
  from a commit no real bootstrap has proven (Cirrus: `tag.yml`,
  `testing/tag-gate.sh`). Until there is, a tag is only as proven as the last
  bootstrap someone watched end to end.
- **No teardown.** A trial product — the repo, two Supabase projects, the
  KV namespaces and Hyperdrive configs, the workers — is removed by hand
  (Cirrus: `testing/teardown.sh`).

## Troubleshooting

Most rows were hit on real bootstraps of Lumen or its sibling Cirrus, which
runs the same engine; the rest are refusals the blueprint now makes on
purpose, written down so they read as instructions rather than breakage.

| Symptom | Cause → fix |
|---|---|
| `01-scaffold` parks: `waiting for github for <org> (connected: <account>)` | The workspace's GitHub connection is to a different account than the one the product repository will live under, so the platform would never see its pull requests. Connect the GitHub App installation on `<org>` to the workspace (console → Integrations → GitHub), then `--resume`. |
| `01-scaffold` stops: `<org>/<repo> is not linked to workspace <ws>` | The credential could not link the repo and the platform has not. Allow-list it (console → Settings → Git repos) or `orun cloud link --org <ws>` with a user session, then re-run the phase. Without the link every convergence lane dies at the OIDC exchange. |
| `03-infrastructure` waits on connections, then stops | Consent not granted yet — console → Integrations, then re-run the phase. The probe is a *wait*, not a failure. |
| `03-infrastructure` reconcile refused: `parent_grant_insufficient` | The Cloudflare token's permission groups do not cover a template (usually Hyperdrive Write). Re-issue the token, re-connect, re-run the phase. |
| A phase refuses with `requires: 02-foundation (pending)` | Its predecessor has not been placed into this `--out`. Run that phase, or `--resume`. A predecessor that is `drifted` SATISFIES the requirement — its files are all there. |
| `--resume` prints "leaving 01-scaffold as placed" | Expected after branding. Every file is present but differs from the blueprint, so the phase is `drifted` and re-placing it would revert your product's identity. Re-place one deliberately with `--phase <name>`. |
| Secrets listed `orphaned` | Their connection was revoked or replaced (e.g. the Supabase OAuth app's scopes changed). Re-connect the provider and re-run `--phase 03-infrastructure`: the reconcile re-mints only the missing keys against the ACTIVE connection. |
| Secret WRITE fails `not_found` while listings work | The API key's role is below ADMIN (resource-hiding masks the denial). Re-mint the key with the admin role; the reconcile is idempotent. |
| Supabase lane: `does not support oauth access` on `/billing/addons` | Provider ≥ 1.6.0 sneaked in — the root pins `~> 1.5.1`; keep the pin. |
| Supabase lane: duplicate project name | The organization already has `<repo>-<env>` (a half-torn-down previous attempt). Adoption imports it automatically when it is the *same* product re-bootstrapping; otherwise delete the stray project. Adopting resets the database password (see [03-infrastructure.md](docs/phases/03-infrastructure.md)). |
| Terraform: resource already exists (10014 etc.) with empty platform state | `adopt.tf` imports at plan time — present in the kv, hyperdrive and supabase roots. Roots without adoption must be state-migrated or the resource deleted. |
| `03-infrastructure-database` refuses: `SUPABASE_*` not published | `03-infrastructure`'s supabase apply did not publish on that environment. Read that lane, fix, re-run `03-infrastructure`. |
| `04-workers` refuses: `WIRING_*` not published | Phase 03 did not finish — `WIRING_CLOUDFLARE_KV` is `03-infrastructure`'s, `WIRING_CLOUDFLARE_HYPERDRIVE` is `03-infrastructure-database`'s. |
| Cloudflare 10143 (service binding target not found) in `04-workers` | A feedback edge the strip does not cover. Run `node <baseline>/tooling/bootstrap/cycle-break.mjs --check` from the product repo; add the edge to `FEEDBACK_EDGES` and to the acknowledged-cycles test together. |
| api-edge deploy: `Service binding '<NAME>_WORKER' … not found` | A fleet worker never deployed in phase 04. Resume that convergence, then re-run `05-edge`. |
| Convergence run fails, lanes look transient | `orun.run/watch@v1` already resumes it up to 3× (`gh run rerun --failed` is a true resume: exec-id + `--retry`). |
| Convergence still red after the resume budget | Re-running the phase lands nothing new, and CI plans `--changed`, so nothing redeploys what the failed run left undeployed. Resume the run itself — `gh run rerun --failed <run-id>` — then re-run the phase so its `await` hooks verify. |
| `/health` probes fail against a green deploy | Check `subdomain` first: it must be the Cloudflare account's workers.dev subdomain, and the default is a placeholder. |
| CLI login dies with 429 `rate_limited` | Fixed ≥ v2.48.1 (redeem honours Retry-After). Upgrade the CLI. |
| `unknown flag: --phase`, `cannot unmarshal !!map into []scaffold.Hook`, or an action `has no parameter "githubOwner"` / `"sha"` | The CLI is below the v2.58.11 floor. This blueprint is not readable by an older one. |
| A fresh build stops before 01-scaffold: `✕ phase "04-workers" precondition "wiring" is not met: … project "<repo>" not found` | The CLI is below v2.58.10, which asks the preflight about the product's project before phase 01 has created it and calls the answer a failure. Upgrade; the probe is then deferred to phase 04. |
| The product's `intent.yaml` says `workspace: ws_SET_ME`, or its secret refs name the repository (`secret://<repo>/…`) | `orunWorkspace` was empty: set it, or run the build in the workspace (ORUN_WORKSPACE) with a CLI ≥ v2.58.11, which fills it from there. |
| `✕ input "productdomain" is required` | Required inputs are validated before anything else, so this names the key nobody typed. All four — `reponame`, `productname`, `productdomain`, `githuborg` — must be set on every invocation, including single-phase ones. `--values <out>/.rebrand/values.json` carries them. |
| Console/edge smoke fails right after the FIRST deploy of a worker | workers.dev route propagation race — the deploy lane's smoke retries with backoff (stack-tectonic ≥ 0.18.2); a convergence resume clears older pins. |
| Terraform lane: "state already locked" by ITS OWN plan | Backend lock-release race — a convergence resume clears it. |
| Lanes fail with NO logs at all | GitHub Actions billing or spending limit. The message lives only in the check-run annotations (`gh api repos/<o>/<r>/check-runs/<job-id>/annotations`). |
| Environment cannot observe GitHub Actions (gh 403) | `orun.pr/land@v1` and `orun.run/watch@v1` fall back to plain REST automatically. If even REST Actions is blocked, the watch reports it rather than hanging — verify the run out of band before the next phase. |
| Many lanes queued, none claiming | Runner-pool starvation — `max-parallel: 8` in `ci.yml` is deliberate (the resolve herd); patience, or check the run is not superseded. |

## Architecture invariants this depends on

- **Phase state is derived, never stored.** Nothing in `--out` records which
  phases have run; the engine asks the tree. A stored file would be a cache,
  and it must always be safe to delete — which is what makes a phase runnable
  alone, months later, from a fresh container. The one record a later phase
  reads, `.rebrand/values.json`, is product content, committed, and says who
  the product is — not how far its bootstrap got.
- **The product's CI holds one credential: `GITHUB_TOKEN`.** Provider
  credentials are brokered per run from workspace integrations; terraform
  state lives on the platform (`backend "http"`, run-token auth); terraform
  outputs travel as lease-published job-output secrets. No AWS, no Secrets
  Manager, no long-lived provider tokens on any deploy path. The bootstrap's
  own secret hooks hold no value either: a brokered secret is a pointer at a
  connection and a scope template, minted just-in-time at resolve.
- **Every phase is a pull request that is verified, then merged.** PR runs
  carry remote state so lanes resolve their secrets there too; nothing
  mutating runs on a PR (deploy and apply profiles are gated on a push to
  `main`). That is the reason phase 03 is two landings.
- **Resume-capable CI**: exec-id is the GitHub run id (no attempt suffix) and
  every re-run lane passes `--retry` — `gh run rerun --failed` is a true
  resume.
- **`cloudflare-domain` is the only component parked by design**; every
  other component deploys on the merge that lands it.
