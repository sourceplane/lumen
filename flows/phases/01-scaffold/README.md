# Phase 01 — scaffold

Births the product repo from the **workspace blueprint**
(`flows/phases/01-scaffold/blueprint.yaml`) and connects it to its Orun Cloud
workspace. After this phase the repo exists on GitHub, CI runs on every
push, and every later phase can find the product's identity inside the
repo itself.

This is the only phase that takes identity inputs.

## What it lands

The repo ROOT — no deployable components yet:

- `intent.yaml` (workspace AND project written in), `.github/workflows/ci.yml`
  (resume-capable CI: exec-id = run id, conditional `--retry`,
  `max-parallel: 8`, lane pin orun ≥ v2.52.4)
- `tooling/` — ONLY what product builds use: `eslint`, `tsconfig`, `wire`
- `ai/context/` — fresh, product-only agent context: `current.md`,
  `decisions.md`, `open-risks.md`, plus the `operations.md` contract and
  the `deployment.md` placeholder that phase 08 fills
- `.rebrand/values.json` — the identity record every later phase reads
- root files: `package.json`, `pnpm-workspace.yaml`, `pnpm-lock.yaml`,
  `turbo.json`, `kiox` locks, `.gitignore`, `README.md` (product-only —
  the forking narrative is stripped), `.vscode/`
- empty discovery roots `apps/ infra/ packages/ tests/` (with `.gitkeep`)
  so `orun new`'s repo-scale gate and the product CI can plan from birth

**What deliberately does NOT land**: this baseline's machinery — `flows/`,
`agents/`, rebrand/fork/blueprint tooling, baseline working notes,
provenance files. A product carries product files only and its docs never
present it as a copy of anything.

## Inputs

| input | example | notes |
|---|---|---|
| `out` | `$HOME/sourceplane/acme` | created if absent |
| `workspace` | `ws_FGBDTQ8T` | id or slug |
| `reponame` | `acme` | lowercase slug; repo becomes `<githuborg>/<reponame>` |
| `productname` | `Acme Cloud` | display name |
| `productdomain` | `acme.dev` | product domain |
| `subdomain` | `rahulvarghesepullely` | workers.dev subdomain — keeping the baseline's is supported (worker names are brand-prefixed) |
| `githuborg` | `sourceplane` (default) | |
| `dryrun` | `false` (default) | `true` renders into a temp dir, reports the file count, creates nothing |

## Steps

1. **blueprint** — `orun new` applies the workspace blueprint (no hooks:
   the blueprint's hook chain ends in a full-tree gate; the useful hooks
   are replicated inline), then `git init`, rebrand
   (`tooling/rebrand/rebrand.mjs --values .rebrand/values.json`), and the
   intent `workspace:` rewrite.
2. **repo — THE GitHub repo creation step.** This is where the repo comes
   to exist on the git side; no other phase touches repo creation. Three
   states are supported, in order:
   - `origin` already wired locally → push;
   - the repo was **pre-created on GitHub** (org policy may restrict repo
     creation to admins — create it empty, no README) → the step detects
     it (`gh repo view`), wires `origin`, and pushes;
   - nothing exists anywhere → `gh repo create <githuborg>/<reponame>
     --private --source . --push`.

   Requires `gh` authenticated with repo-creation (or at least push)
   rights on `<githuborg>`.
3. **link** — `orun cloud link --org <workspace>` + `orun cloud check`
   (records the numeric repo id the CI OIDC exchange resolves by, and
   allow-lists CI). Runs after **repo** because the link resolves the git
   remote — which is also why repo creation lives in THIS phase and not
   later: everything after phase 01 assumes a pushed, linked repo.

## Verify / done means

The repo is on GitHub, main is pushed, and `orun cloud check` passes. The
first CI run plans zero components and is trivially green.

## Re-running

Idempotent: `orun new` is additive, rebrand is a no-op on branded files,
`git init`/`gh repo create` are guarded, `cloud link` re-links harmlessly.
If `cloud check` still fails after link, grant the repo in the console
(Git Repos) and re-run the phase.

## Example commands

From the baseline checkout (local mode):

```bash
orun workflow run flows/phases/01-scaffold/workflow.yaml \
  --set out=$HOME/sourceplane/acme \
  --set workspace=ws_ABCD1234 \
  --set reponame=acme \
  --set productname="Acme Cloud" \
  --set productdomain=acme.dev \
  --set subdomain=rahulvarghesepullely
```

Headless (fresh container / no checkout — see BOOTSTRAP.md §3c): same
command by remote reference, with `ORUN_TOKEN` + `GITHUB_TOKEN` exported
and `--set repo=<owner/name>` instead of `out`:

```bash
export ORUN_TOKEN="$(orun auth token | tail -1)" GITHUB_TOKEN=…
orun workflow run github:sourceplane/lumen@main//flows/phases/01-scaffold/workflow.yaml \
  --set workspace=ws_ABCD1234 \
  --set reponame=acme \
  --set productname="Acme Cloud" \
  --set productdomain=acme.dev \
  --set subdomain=rahulvarghesepullely
```

Preview with zero side effects (either mode): append `--set dryrun=true` —
the blueprint is applied, shown, and reverted; nothing is pushed or
deployed. Re-running a completed phase is always safe (idempotent): the
apply is a no-op, the landing finds nothing, and verify re-asserts.

Pre-created repo: if `sourceplane/acme` already exists on GitHub (empty —
org policy may restrict creation to admins), the repo step detects it,
wires `origin`, and pushes into it instead of creating.

## Next

[Phase 02 — foundation](../02-foundation/README.md).
