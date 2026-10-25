# Phase 01 — scaffold

Births the product repo from `repo-blueprint.yaml`'s `01-scaffold` phase and
connects it to its Orun Cloud workspace. After this phase the repo exists on
GitHub, CI runs on every push and pull request, and every later phase can
find the product's identity inside the repo itself.

This is the only phase that creates anything on GitHub, and the only one
whose inputs are the product's identity rather than a reading of it.

## What it lands

The repo ROOT — no deployable components yet:

- `intent.yaml`, with the product's workspace written into `workspace:`;
  `ci.yml` (resume-capable CI: exec-id = run id, `--retry` on re-run
  attempts, `max-parallel: 8`, `--remote-state` on pull requests too, lane
  pin orun v2.56.2)
- `tooling/` — ONLY what product builds use: `eslint`, `tsconfig`, `wire`
  (the deploy-time wrangler renderer)
- `ai/context/deployment.md` (the placeholder `08-docs` fills) and
  `ai/context/operations.md` (the standing operating contract) — exactly
  these two files, one module each, so a new file in `ai/context/` cannot
  ship by accident
- `.rebrand/values.json` — the identity record every later phase reads
- root files: `package.json`, `pnpm-workspace.yaml`, `pnpm-lock.yaml`,
  `turbo.json`, `.gitignore`
- `README.md` and `AGENTS.md` — the product's own, rendered from
  `.baseline/product/` with its name and repository: the front page, and the
  page an agent handed the product reads first (what it is, what to read
  next, how a change lands, what not to touch)
- empty discovery roots `apps/ infra/ packages/ tests/` (with `.gitkeep`) so
  `orun new`'s repo-scale gate and the product CI can plan from birth

**What deliberately does NOT land**: this baseline's machinery —
`repo-blueprint.yaml`, `blueprint.yaml`, `BOOTSTRAP.md`, this repository's
own `README.md`, `docs/phases/`, `agents/`, `specs/`, `tasks/`, `hooks/`,
`testing/`, `.vscode/` (its agent loop), the rebrand, bootstrap, fork and
migration tooling, and `baseline.yml` (the factory's own CI, which
the blueprint's `ignore` list keeps out of the `.github` copy). A product
carries product files only, and its docs never present it as a copy of
anything. `testing/leak.test.sh` derives what every phase would place and
gates the set, so the promise is a test rather than a claim.

## Inputs

| input | example | notes |
|---|---|---|
| `--out` | `$HOME/sourceplane/acme` | a flag, not an input; created if absent |
| `reponame` | `acme` | REQUIRED. Lowercase slug (`^[a-z][a-z0-9-]*$`); repo becomes `<githuborg>/<reponame>` |
| `productname` | `Acme Cloud` | REQUIRED. Display name |
| `productdomain` | — (default empty) | NOT ASKED. Empty brands the placeholder `<reponame>.example.com` where the domain goes, for an owner to replace later; pass it only for a product that already has its domain |
| `githuborg` | `sourceplane` | REQUIRED. The org or user the repo is created under |
| `orunWorkspace` | `ws_ABCD1234` | workspace id. Unset, the workspace the build runs in (ORUN_WORKSPACE); with none anywhere, the placeholder `ws_SET_ME` |
| `subdomain` | `rahulvarghesepullely` | workers.dev subdomain of the Cloudflare account you deploy into — every URL derives from it (worker names are brand-prefixed, so keeping the baseline's account is supported). A console or `--from bst_…` build reads it from the Cloudflare connection; pass it only for a hand-run build |
| `apibaseurl` | — (default empty) | CLI default API base; empty derives `https://api.<productdomain>`, or with no domain the prod edge, `https://<brandSlug>-api-edge-prod.<subdomain>.workers.dev` |
| `repoPrivate` | `true` (default) | visibility at creation only |
| `epicSlug` | `infra-baselining` (default) | the epic every phase files its task under |

The full set, rebrand overrides included, is in the
[phases README](README.md#inputs) and `repo-blueprint.yaml`'s `inputs:`
block.

## Steps

1. **requires.probe** — `orun.doctor/check@v1` with `providers: [github]`
   and `githubOwner: <githuborg>`, waiting up to 10 minutes. The platform
   learns of a pull request only through the GitHub App installation on the
   account that OWNS the repository; a workspace connected to some other
   account passes "github is connected" and never sees a single PR of the
   product it builds. So the owner's connection is asked for before a repo
   exists, and waited for like any other consent.
2. **pre** — `orun.task/ensure@v1` twice: the epic (by `epicSlug`), then this
   phase's task under it.
3. **place** — the engine writes this phase's modules into `--out`.
4. **the identity chain**, as `post` hooks in order: `git init` → `git add`
   → `tooling/rebrand/rebrand.mjs --values .rebrand/values.json` → the
   `orun-workspace` rewrite of `intent.yaml` → `git add` → `rebrand.mjs
   --verify` → `pnpm install --lockfile-only`. The chain was the blueprint's
   global `postInstantiate` once, because a one-shot instantiation has only
   one end; in a phased bootstrap the end of `01-scaffold` IS that moment.
   It is also why every later phase derives as `drifted` rather than `done`.

   The `workspace:` rewrite exists because rebrand classifies the orun state
   backend as org-owned and leaves it alone — without it the product's CI
   would claim the BASELINE's workspace on every remote operation. It fails
   only when `intent.yaml` has no `workspace:` line; a line that already
   names the workspace (a build into the one the baseline declares, or a
   re-run) is nothing to do.
5. **repo — THE GitHub repo creation step**, an `orun.repo/ensure@v1` hook.
   Three states are supported:
   - `origin` already wired locally → push;
   - the repo was **pre-created on GitHub** (org policy may restrict repo
     creation to admins — create it empty, no README) → the action finds
     it, wires `origin`, and pushes;
   - nothing exists anywhere → it is created under `githuborg`, private
     unless `repoPrivate=false`.

   Requires a `GITHUB_TOKEN` with repo-creation (or at least push) rights
   on `githuborg`.
6. **link** — `orun cloud link --org <workspace>` (best effort), then
   `orun cloud check --org <workspace>` as the gate. Every convergence lane
   authenticates over GitHub OIDC, and the platform resolves that token
   through the repo link; an unlinked repo fails every lane of the first
   real convergence with `OIDC exchange rejected: Not found`. The link is
   best effort because a workspace-scoped key may not write links (the
   platform may have linked the repo already); the check is not, so an
   unlinked repo stops here, naming the fix, instead of an hour later in
   every lane.
7. **land** — `orun.pr/land@v1`. The empty repo is seeded with one commit on
   `main`, and the scaffold arrives as PR #1 from `orun/BASE-<n>-01-scaffold`,
   bound to the phase's task. It merges once that PR's CI run is green —
   which it is trivially, since the scaffold carries no components to plan.

This phase has no `await` hook: there is nothing to converge until a later
phase lands a component.

## What it defers for the rest of the bootstrap

Two rules in `intent.yaml` are right for a live product and wrong for a build
of one, so this phase turns both off and `08-docs`, the last landing, puts
them back byte-for-byte:

- `prod.promotion.dependsOn: [stage]` makes every prod deploy wait out the
  same component's stage deploy, doubling each convergence — twelve workers'
  worth of it in `04-workers`. During a bootstrap both environments are empty
  and every phase is watched to green, so the gate protects nothing yet
  (`tooling/bootstrap/promotion.mjs --defer`).
- dev's `github-push-main` activation re-verifies every component on the dev
  rung on every merge, which during a bootstrap proves nothing the pinned
  baseline's own CI did not and takes runner slots from the deploys
  (`tooling/bootstrap/dev-lanes.mjs --defer`). Pull requests keep their dev
  lanes throughout.

Both are deferred, never dropped: a bootstrap that stops before `08-docs`
leaves a marker comment in `intent.yaml`, and `--restore` (or a re-run of
`08-docs`) is the whole fix. `testing/bootstrap-defer.test.sh` holds the
round trip exact.

## Verify / done means

The repo is on GitHub, `main` carries the scaffold, `orun cloud check`
passes, and the phase's task is on the epic. The first CI run plans zero
components and is trivially green.

## Re-running

Idempotent: placement is additive, rebrand is a no-op on branded files, and
`git init` / the workspace rewrite / repo-ensure / link are guarded. Once the tree is branded this
phase derives as **`drifted`**, not `done` — so `--resume` leaves it alone
rather than reverting the product's identity to `lumen`. Re-place it
deliberately with `--phase 01-scaffold`.

## Troubleshooting

- **Parks with `waiting for github for <org> (connected: <account>)`** — the
  workspace's GitHub connection is to a different account than the one the
  repo will live under. Connect the GitHub App installation on `<org>` to the
  workspace (console → Integrations → GitHub); the probe picks it up while
  it waits, or re-run the phase.
- **`link` fails: `<org>/<repo> is not linked to workspace <ws>`** — the
  credential could not link it and the platform has not either. Allow-list
  the repo (console → Settings → Git repos) or run `orun cloud link --org
  <ws>` with a user session, then re-run the phase.
- **`intent.yaml` says `workspace: ws_SET_ME`, or the secret refs name the
  repository (`secret://<repo>/…`)** — `orunWorkspace` was empty and the
  build did not run inside a workspace. Set it, or run inside the workspace
  with a CLI ≥ v2.58.11, which fills it from there.
- **A classic PAT is refused pushing CI files** — classic PATs and gh OAuth
  tokens need the `workflow` scope to push anything under `.github`;
  fine-grained PATs need only `contents: write`.

## Example commands

From the baseline checkout (local mode):

```bash
orun new --blueprint repo-blueprint.yaml \
  --out $HOME/sourceplane/acme --run-hooks --phase 01-scaffold \
  --set reponame=acme \
  --set productname="Acme Cloud" \
  --set githuborg=sourceplane \
  --set orunWorkspace=ws_ABCD1234 \
  --set subdomain=rahulvarghesepullely
```

Headless (fresh container / no checkout — see BOOTSTRAP.md §2): clone the
baseline at a tag and run the same command, with `ORUN_TOKEN` +
`GITHUB_TOKEN` exported:

```bash
export ORUN_TOKEN="$(orun auth token | tail -1)" GITHUB_TOKEN=…
git clone --depth 1 --branch <baseline-tag> https://github.com/sourceplane/lumen
cd lumen
orun new --blueprint repo-blueprint.yaml \
  --out /work/acme --run-hooks --phase 01-scaffold \
  --values /work/acme.values.yaml
```

Preview with zero side effects: drop `--run-hooks` — the phase places files
into `--out` and stops, with no `git init`, no rebrand, no repo and no
landing. `--status` derives every phase's state and writes nothing at all.

From here on, the product's own `.rebrand/values.json` is a complete values
file for every later phase (`--values $HOME/sourceplane/acme/.rebrand/values.json`).

## Next

[Phase 02 — foundation](02-foundation.md).
