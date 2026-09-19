# Phase 02 — foundation

Lands the **shared packages** — thirteen modules (`repo-blueprint.yaml`,
phase `02-foundation`) — that everything later builds on. Nothing deploys and no
provider connection is needed — the PR's verify lanes (turbo builds and
tests) are the whole gate, run once on the PR and again on `main`.

## What it lands

`packages/`: `cli`, `contracts`, `db`, `notifications-client`,
`policy-engine`, `sdk`, `shared`, `testing`, `webhook-verifier` — plus the
test suites for `contracts`, `db`, `notifications-client` and
`policy-engine` under `tests/`. Each is a `turbo-package` component whose
lanes build and test it in CI.

`packages/db` carries the Postgres schema and its migrations, but nothing
applies them yet: the migration runner (`infra/db-migrate`) lands in
`03-infrastructure-database`, once there is a database to apply them to.

## Inputs

`--out` is the product repo. The blueprint's required inputs — `reponame`,
`productname`, `productdomain`, `githuborg` — are validated before any phase
runs, so pass them on every invocation; the product's own
`.rebrand/values.json` is a complete values file. See
[the phases README](README.md#inputs).

## Steps

1. **requires** — `01-scaffold` must be placed in `--out`.
2. **pre** — `orun.task/ensure@v1`: this phase's task under the epic.
3. **place** — the engine writes this phase's modules into `--out`. They
   arrive speaking `lumen`, because `01-scaffold`'s rebrand ran before they
   existed.
4. **brand** — `git add -A` → `rebrand.mjs --values .rebrand/values.json` →
   `git add -A` → `rebrand.mjs --verify`, which refuses a landing with the
   baseline's identity left in it.
5. **lockfile** — `pnpm install --lockfile-only`. `01-scaffold` wrote the
   lockfile for the projects that existed then, and the lanes install with
   `--frozen-lockfile`; without this step every package was refused before
   a test ran (`ERR_PNPM_OUTDATED_LOCKFILE`).
6. **land** — `orun.pr/land@v1`: PR `phase(02-foundation): shared packages`,
   waits for its verify lanes, merges.
7. **converge** — `orun.run/watch@v1` (an `await` hook) watches the run for
   the merged commit and resumes transient lanes up to three times.

## Verify / done means

The main convergence run is green — every package builds and its tests
pass in the product repo.

## Troubleshooting

- **PR lanes fail building a package**: the baseline's packages are
  self-contained; a failure here usually means a partial placement (re-run
  the phase — placement is additive) or lockfile drift.
- **`ERR_PNPM_OUTDATED_LOCKFILE`**: the lockfile step did not run or did not
  land. Re-run the phase; `pnpm install --lockfile-only` is idempotent.
- **`rebrand --verify` refuses**: a placed file still carries the baseline's
  identity. The message names the file. That is a rebrand rule missing in
  this baseline, not something to hand-edit in the product.
- **The landing picks up edits you did not intend**: commit or stash your
  local changes in the product repo before running a phase.
  `orun.pr/land@v1` lands what is in the tree, and a phase is meant to land
  its own modules, not your work in progress.

## Example commands

From the baseline checkout:

```bash
orun new --blueprint repo-blueprint.yaml --out $HOME/sourceplane/acme \
  --run-hooks --phase 02-foundation \
  --values $HOME/sourceplane/acme/.rebrand/values.json
```

Headless (fresh container / no checkout — see BOOTSTRAP.md §2): clone the
baseline at a tag and run the same command, with `ORUN_TOKEN` +
`GITHUB_TOKEN` exported:

```bash
export ORUN_TOKEN="$(orun auth token | tail -1)" GITHUB_TOKEN=…
git clone --depth 1 --branch <baseline-tag> https://github.com/sourceplane/lumen
cd lumen
orun new --blueprint repo-blueprint.yaml --out /work/acme \
  --run-hooks --phase 02-foundation --values /work/acme.values.yaml
```

Preview with zero side effects: drop `--run-hooks` — the phase places files
and stops, with no landing, no convergence watch and no probe. `--status`
derives every phase's state and writes nothing at all. Re-running a
completed phase is safe: the placement is a no-op, the landing finds
nothing new, and the `await` hooks re-assert.

## Next

[Phase 03 — infrastructure](03-infrastructure.md).
