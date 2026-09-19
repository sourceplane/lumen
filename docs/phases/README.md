# The phases — one blueprint, ten selections

`repo-blueprint.yaml` declares ten phases that take a product from
**nothing** to a **live, documented baseline** on Cloudflare and Supabase.
Run them one at a time at your own pace with `--phase <name>`, or run the
whole sequence unattended with `--resume`. There is no wrapper that runs
the others and no per-phase workflow file: a phase is a selection on one
artifact, which is what makes running one alone, months later, from a fresh
container the same operation as running them all.

Each phase follows the same contract:

> **place its modules → brand them → land them as a pull request that must go
> green before it merges → watch the convergence the merge starts
> (auto-resumed) → verify the outcome is actually there.**

Run from the baseline checkout (the blueprint's only source is `path: .`);
the product repo is wherever `--out` points.

## Execution order

The phase number is the EXECUTION order — the root scaffold must exist
before anything else can build or deploy, the database must exist before
anything can read it, and a worker cannot bind to a Hyperdrive config that
has not been created. Each phase's `requires.phases` states this in the
document, and the engine refuses a phase whose predecessor is not placed,
naming it.

Every phase lands as a pull request that is verified, then merged: each
landing waits for its PR's whole CI run to finish green (the product's PR
runs carry remote state, so lanes that need secrets resolve them on the PR
too), and the convergence after the merge is still watched, because
deploying is what a merge does and a PR cannot.

| phase | milestone | lands | verified by |
|---|---|---|---|
| [`01-scaffold`](01-scaffold.md) | 01-scaffold | **GitHub repo created** + repo born: intent, CI, tooling, identity | repo pushed + `orun cloud check` |
| [`02-foundation`](02-foundation.md) | 02-foundation | 13 shared packages | convergence green |
| [`03-infrastructure`](03-infrastructure.md) | 03-infrastructure | `supabase`, `cloudflare-kv` | `WIRING_CLOUDFLARE_KV` + `SUPABASE_PROJECT_REF` / `SUPABASE_DB_PASSWORD` / `SUPABASE_DB_URL` published on stage and prod |
| [`03-infrastructure-database`](03-infrastructure.md#the-second-landing-03-infrastructure-database) | 03-infrastructure | `cloudflare-hyperdrive`, `db-migrate` | `WIRING_CLOUDFLARE_HYPERDRIVE` published on stage and prod |
| [`04-workers`](04-workers.md) | 04-workers | the 12-worker fleet, two feedback bindings stripped | convergence green |
| [`04-workers-restore`](04-workers.md#the-second-landing-04-workers-restore) | 04-workers | the two bindings put back (places no files) | convergence green |
| [`05-edge`](05-edge.md) | 05-edge | `api-edge` (+ its tests, + `platform-limits-tests`) | `/health` answers on stage and prod |
| [`06-console`](06-console.md) | 06-console | web console | console + edge live on stage and prod |
| [`07-domain`](07-domain.md) | 07-domain | custom domain (OPTIONAL — `when: inputs.domain`) | convergence green |
| [`08-docs`](08-docs.md) | 08-docs | live-deployment docs (places no files; a hook renders them) | the URLs the manifest claims, re-probed |

Ten phases, eight milestones. `03-infrastructure-database` and
`04-workers-restore` are second landings of the unit before them: each has
its own PR and its own task, and each files under its predecessor's
milestone. They are documented on their predecessor's page for the same
reason.

Two requirements look odd and are deliberate:

- **`05-edge` requires `04-workers`, not `04-workers-restore`.** A phase
  that places no files derives as `unknown` — the product repo cannot be
  asked whether a landing happened — and `requires.phases` fails closed on
  `unknown`. A requirement on a hook-only phase could never be satisfied.
  Order in the document is what sequences a run; `requires` is the gate
  that catches a phase run against a tree where its predecessor never
  happened. `testing/phases.test.sh` refuses a requirement on a hook-only
  phase.
- **`08-docs` requires `06-console`, not `07-domain`**, so a bootstrap that
  skips the custom domain still reaches it.

## Inputs

The keys are the console card's (`blueprint.yaml`), lowercase, so what an
operator types in the console form and what the blueprint declares are the
same words.

| input | required | notes |
|---|---|---|
| `reponame` | yes | lowercase slug (`^[a-z][a-z0-9-]*$`); the repo becomes `<githuborg>/<reponame>`, and it prefixes the Supabase projects and every worker. The console fills it from the chosen repository |
| `productname` | yes | display name |
| `productdomain` | yes | the apex domain the product answers on; it does not need to exist yet |
| `githuborg` | yes | the org or user the repo lives under. The console fills it from the chosen repository's owner |
| `subdomain` | — | the Cloudflare **account's** workers.dev subdomain. The default is a placeholder; see below |
| `apibaseurl` | — | the CLI/SDK default API base; empty means `https://api.<productdomain>` |
| `orunWorkspace` | — | workspace id. Unset, it is the workspace the build runs in (`from: workspace`, ORUN_WORKSPACE, which a console build always has); with none anywhere, 01 writes the placeholder `ws_SET_ME`, which fails loudly rather than silently cross-tenanting |
| `epicSlug` | — | default `infra-baselining`; the epic every phase files its task under, found by slug so a fresh run and a resumed run find the same work |
| `repoPrivate` | — | default `true`; applied only when `01-scaffold` creates the repo — an existing repo keeps its visibility |
| `domain` | — | default `false`; `true` runs `07-domain` (read that page first) |
| `pascalName`, `brandSlug`, `cliBin`, `salesEmail` | — | rebrand overrides. Empty, the first three derive from the names above (`brandSlug`, the worker prefix, from `reponame`); an empty `salesEmail` keeps the baseline mailbox |

**`subdomain` is not the product name.** Every generated URL and the
api-edge CORS allowlist derive from it, so a wrong value ships a product
that deploys cleanly and is unreachable at every address it advertises —
and the `/health` probes of 05, 06 and 08 fail against hosts that were never
going to exist. Find it under Workers & Pages in the Cloudflare dashboard.

`01-scaffold` writes the answers into the product as
`.rebrand/values.json`, which is committed. Every later phase's rebrand hook
reads it, and it carries `githuborg`, `epicSlug` and `domain` too, so a phase
run months later in a fresh container can recover what the operator
answered (orun's own record, `.orun/provenance.lock`, is gitignored and does
not survive a container). The blueprint's **required** inputs are still
validated before any phase runs, so they must be supplied on every
invocation, single-phase ones included. The file uses the blueprint's own
input keys, so the simplest values file for a later phase is that file:

```bash
orun new --blueprint repo-blueprint.yaml \
  --out $HOME/sourceplane/acme --run-hooks --phase 03-infrastructure \
  --values $HOME/sourceplane/acme/.rebrand/values.json
```

Drop `--run-hooks` (or use `--status`) to preview. Without it a phase places
files and stops: no repo, no landing, no convergence watch, and no probe —
which is exactly what makes a dry instantiation of this baseline possible in
CI with no workspace and no provider (`testing/placement.test.sh` does this).

## Headless / container mode

A fresh container with two env tokens is the entire contract (see
[BOOTSTRAP.md §2](../../BOOTSTRAP.md#2-headless--container-mode-daytona-ci-any-sandbox)).
Clone the baseline at a tag and the tag pins everything: the blueprint, its
modules, and the scripts its hooks run all come from that one commit, and
orun pins the checkout by digest into its object store before any module is
read.

```bash
export ORUN_TOKEN=… GITHUB_TOKEN=…
git clone --depth 1 --branch <baseline-tag> https://github.com/sourceplane/lumen
cd lumen
orun new --blueprint repo-blueprint.yaml --out /work/acme --run-hooks \
  --phase 03-infrastructure --values /work/acme.values.yaml
```

Inside a baseline checkout the same command uses the local tree: the two
modes are the same files.

## Unattended: `--resume`

`--resume` places every phase not already derived as done, in dependency
order, honouring each barrier. Budget **about 75 minutes** on a clean run —
the card's `expectedMinutes`, and close to the ~73 minutes measured for
phases 01–06 under the shell layer this replaced. The worker fleet (~31m)
and the console build (~16m) dominate; Supabase project creation (5–7m) is
the longest single wait and cannot be engineered away from our side. Where
each number comes from, and which are estimates: [TIMINGS.md](TIMINGS.md).

Why it can run unattended:

- **Idempotence, everywhere.** Landings and the convergence watch fall back
  to plain REST when `gh` is degraded, smokes retry route propagation,
  and `orun.run/watch@v1` resumes failed lanes up to three times. A phase
  that failed partway resumes by being re-run.
- **Waits are declared, not slept.** `01-scaffold` waits for a GitHub
  connection to the account that will own the repo; `03-infrastructure`
  waits up to 10 minutes for the GitHub, Cloudflare and Supabase consents;
  `03-infrastructure-database` will not start until supabase's outputs are
  published; `04-workers` will not start until both `WIRING_*` keys are. A
  consent nobody has clicked is a *wait*, not a failure.
- **Verification is the phase's own last act.** `await` hooks re-list the
  published secrets on both environments and re-probe the live endpoints,
  trusting no earlier step's word.

## Pacing, idempotence, resume

- Run one phase today and the next whenever. Nothing expires between
  phases; each phase re-asks its own preconditions.
- **Phase state is derived from the tree, never stored.** Nothing in
  `--out` records which phases have run. A stored file would be a cache,
  and it must always be safe to delete.
- A phase whose files are all present but differ from the blueprint derives
  as **`drifted`** — which is every phase once `01-scaffold` brands the
  tree. Drift SATISFIES a successor's requirement (the files are all
  there), and `--resume` leaves a drifted phase placed rather than
  reverting your product's identity to `lumen`. Re-place one deliberately
  with `--phase <name>`.
- `04-workers-restore` and `08-docs` place no files, so they derive as
  `unknown`; `07-domain` derives as `skipped` unless `domain=true`.
  `--status` prints all of this without writing anything.
- **Git-level idempotence is not deploy-level idempotence.** The product's
  CI plans `--changed`: a component deploys only when its files changed in
  the push. If a convergence is still red after the watch has spent its
  resume budget, the content is already on `main`, so re-running the phase
  lands nothing new and no push will redeploy what the failed run left
  undeployed. Resume the failed run itself — `gh run rerun --failed
  <run-id>` is a true resume (the exec-id is the run id and every lane
  passes `--retry`) — then re-run the phase so its `await` hooks verify.
  This is not hypothetical: a Lumen product bootstrapped before the shell
  layer learned it took three full restarts and never deployed six of its
  twelve workers — it surfaced only when api-edge's deploy failed on a
  service binding to a worker that did not exist.

## Prerequisites (once)

1. `orun auth login --device` (approve at app.orun.dev/cli/device), or an
   `ORUN_TOKEN` for a headless run.
2. A workspace for the product; note its `ws_…` id.
3. Three integrations connected in that workspace:
   - **GitHub** — the App installation on `githuborg`. `01-scaffold` checks
     the connection is to the account that will own the repo and waits for
     it: the platform sees a product's pull requests only through that
     installation.
   - **Cloudflare** — the Account API token, pasted through the console's
     Connect recipe.
   - **Supabase** — the OAuth consent (or a personal access token), bound to
     the organization that will own `<reponame>-stage` and `<reponame>-prod`.

   `03-infrastructure` polls for all three for up to 10 minutes, so the
   consents can be clicked while it waits. Details, including what each
   token must be able to mint: [03-infrastructure.md](03-infrastructure.md).
4. An **admin-role** API key. The first credential WRITE is
   `03-infrastructure`'s secret reconcile, so a builder/viewer key gets
   through `01-scaffold` and `02-foundation` and stops at phase three with
   the re-mint-as-admin hint. The shell layer probed this at minute two;
   the blueprint does not declare an early write-probe yet.
5. The repo allow-listed in the workspace (console → Settings → Git repos)
   when the credential cannot link it itself — a workspace-scoped key
   cannot. `01-scaffold`'s `link` hook tries `orun cloud link`, then gates
   on `orun cloud check`, and stops naming exactly this step if the check
   fails.

## The mechanism, as typed actions

Everything the phases do that is not placing files is a **typed action** —
a closed registry inside the orun binary, not a script this repo ships:

| action | role |
|---|---|
| `orun.task/ensure@v1` | the phase's task in the workspace's task plane: find-or-create by identity under `epicSlug`, contract attached from `tasks/<phase>.TaskContract.yaml`. `01-scaffold` also ensures the epic itself |
| `orun.repo/ensure@v1` | create the product repo under `githuborg` if it does not exist (`private: repoPrivate`); a pre-created repo is found and used |
| `orun.pr/land@v1` | commit → `orun/<task>-<phase>` branch → PR → wait for the PR's whole CI run (30 minutes by default; 60 for `04-workers`, 45 for `06-console`) → merge → back on `main`, through the provenance pen so the landing binds to the phase's task |
| `orun.run/watch@v1` | watch the run for the commit the landing merged (`sha:`), resuming it through transient failures (`resumeBudget: 3`, 2 for the restore) |
| `orun.doctor/check@v1` | the provider-consent wait — a precondition, not a preamble. With `githubOwner` it also checks the GitHub connection is to the account that owns the repo |
| `orun.secrets/exists@v1` | assert the keys a later phase reads are published, on the project's stage and prod environments |
| `orun.integrations/reconcile@v1` | bring the five brokered provider secrets to their declared state: keys that exist are KEPT, keys that are missing are minted against the ACTIVE connection. It never holds a value — a brokered secret is a pointer at a connection and a scope template |
| `orun.http/probe@v1` | probe the live `/health` and console URLs |

The `run:` hooks that remain are this baseline's own business rather than a
verb any bootstrap needs, and each resolves the baseline checkout as
`{{ .baseline.dir }}`, so a pinned clone pins them too:

- `git init` / `git add -A` — `tooling/rebrand/rebrand.mjs` enumerates the
  tree with `git ls-files`, so every phase stages before it brands;
- `rebrand.mjs --values .rebrand/values.json`, then `--verify`, in every
  phase that places files — orun writes a phase's files on that phase's
  turn, so they arrive speaking `lumen` and are branded before they land;
- `01-scaffold`'s `orun-workspace` rewrite of `intent.yaml`'s `workspace:`
  (rebrand treats the state backend as org-owned and leaves it alone) and
  its `link` step (`orun cloud link`, then `orun cloud check` as the gate);
- `pnpm install --lockfile-only` — the lanes install with
  `--frozen-lockfile`, and the lockfile grows with every phase;
- `tooling/bootstrap/cycle-break.mjs --strip` / `--restore` across the two
  worker landings;
- `hooks/render-deployment-docs.sh`, `08-docs`'s renderer.

## Tracking the bootstrap as work (BT)

`01-scaffold`'s first `pre` hook ensures the epic, by `epicSlug`. Every
phase's `pre` hook then ensures its own task under that epic, with the phase
name as its milestone (the two second landings file under 03 and 04) and the
prefix `BASE`, so its branch reads `orun/BASE-<n>-<phase>`. A run that
starts fresh and a run that resumes find the same work. The contract
templates live in `tasks/` at the repo root, one per landing, named by the
hooks' `contract:` field. `gates: []` is a declaration: merge alone finishes
the task, because the main convergence is the gate the phase *watches*, not
one the plane observes as a PR check. The templates are baseline machinery,
never product content. The whole design:
`specs/epics/saas-baseline-tracking/`.

The console previews the same programme from `blueprint.yaml`'s
`programme:` block — the epic and its eight milestones, with `07-domain`
marked conditional.

## Why there is one document

Until BE1 each phase carried a `blueprint.yaml` slice derived by
`tooling/blueprint/split-phases.py`, and the derivation had to PRUNE every
cross-phase `dependsOn` edge, because a slice that names a module in
another slice does not parse.

The prune is what is really gone. orun's phase overlay enforces the same
barrier by REFUSING a dependency that points forward across it, and a
refusal and a deletion are not the same thing — the splitter was deleting
`supabase`'s `dependsOn: [bootstrap]`, an edge to a module that does not
exist and never has, for as long as it ran. A pruned edge to a module in
no phase looks exactly like a pruned edge to a module in an earlier one.

The same move changed what phase 03 is. The shell layer placed all four
data-plane modules in one phase and merged it without waiting on the PR,
because two of them could never pass there; the blueprint splits them so
that every phase's PR can be verified before it merges. The reasoning is on
[03-infrastructure.md](03-infrastructure.md).

`testing/phases.test.sh` holds the partition, the order, the narration and
this folder to each other: every phase has a page here and every page a
phase.
