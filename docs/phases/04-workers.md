# Phase 04 — workers (two landings)

Lands the **12-worker fleet** in two landings: `04-workers` places the fleet
with two service-binding feedback edges stripped, so first-boot workers can
deploy in DAG order; `04-workers-restore` puts those two bindings back once
every worker they point at exists. Both file under the `04-workers`
milestone.

This is the longest stretch of the bootstrap.

## What it lands

`apps/`: `policy-worker`, `membership-worker`, `events-worker`,
`projects-worker`, `identity-worker`, `config-worker`, `webhooks-worker`,
`notifications-worker`, `metering-worker`, `admin-worker`,
`billing-worker`, `integrations-worker` — plus their test suites under
`tests/`.

Each templated worker's deploy renders its committed
`wrangler.template.jsonc` — `@@wiring(<component>/<env>:<key>)@@` tokens —
from the `WIRING_*` secrets phase 03 published — for the fleet, the
Hyperdrive config id from `WIRING_CLOUDFLARE_HYPERDRIVE` (the KV namespace
is api-edge's, in `05-edge`). Resource ids are never committed. Each
worker reads its own runtime keys wire-now-seed-later: declared now, inert
until seeded, and nothing blocks on them.

The internal workers set `workers_dev: false` — they have no public URL, and
the only way in is a service binding from another worker. That is why this
phase verifies by convergence rather than by probe; `05-edge` is where the
fleet becomes observable from outside.

## Why two landings

The `{billing, membership, events, notifications}` cluster binds to itself —
billing ↔ membership, and membership → notifications → events → membership —
and a Cloudflare service binding cannot name a worker that does not exist
yet (error 10143). So a fresh fleet cannot deploy with its bindings intact:
something in the loop is always first.

`tooling/bootstrap/cycle-break.mjs` holds exactly two acknowledged feedback
edges, `billing-worker → membership-worker` and
`membership-worker → notifications-worker`:

- `--strip` removes those bindings from the two workers' wrangler configs
  (byte-preserving markers) before the first landing — the fleet then
  deploys clean in DAG order;
- `--restore` puts them back byte-for-byte for the second landing, when
  every target exists.

Both are idempotent; `--check` reports the current state.

These edges are not in the module DAG and there is no `cycleBreak:` for orun
to defer: the cycle lives in the wrangler config a deploy reads, not in the
placement order, so orun never sees it. That is why the script survives the
move to one blueprint — it is a deploy-time edit to a file, not an ordering
workaround the DAG could absorb.

The restore is a phase of its own, rather than more hooks on the first,
because it can only run after `04-workers` has CONVERGED, and `post` hooks all
run before `await`: "strip, land, converge, restore, land, converge" cannot
be one phase's hook list. Two units of work that land separately, with two
PRs and two task contracts, are two phases here.

## Inputs

`--out` is the product repo. The blueprint's required inputs — `reponame`,
`productname`, `productdomain`, `githuborg` — are validated before any phase
runs, so pass them on every invocation; the product's own
`.rebrand/values.json` is a complete values file. See
[the phases README](README.md#inputs).

## `04-workers`

1. **requires** — `03-infrastructure-database` placed, and a
   `requires.probe`: `orun.secrets/exists@v1` asserts both
   `WIRING_CLOUDFLARE_HYPERDRIVE` and `WIRING_CLOUDFLARE_KV` on stage and
   prod before a single file is placed. Missing keys mean phase 03 did not
   finish, and the phase says which.
2. **pre** — the phase's task.
3. **place** → **brand** → **lockfile**, then a `post` hook runs
   `cycle-break.mjs --strip`.
4. **land** — PR `phase(04-workers): worker fleet (feedback edges
   stripped)`. The PR's lanes build, test and plan the fleet on two
   environments — nothing deploys from a PR — and the landing waits up to an
   hour for them.
5. **converge** — the merge deploys the fleet. Budget an hour
   (`waitSeconds: 3600`), resumed up to three times. Lanes resolve their
   `WIRING_*` secrets at claim time.

## The second landing: `04-workers-restore`

1. **requires** — `04-workers` placed. It places no files, so it derives as
   `unknown`; that is also why `05-edge` requires `04-workers` rather than
   this phase.
2. **pre** — the task, filed under the `04-workers` milestone.
3. **restore** — `cycle-break.mjs --restore`.
4. **land** — PR `phase(04-workers): restore service-binding feedback
   edges`.
5. **converge** — billing and membership redeploy with their bindings in
   place (resumed up to twice).

## Verify / done means

Both convergence runs green: every worker deployed with the two feedback
bindings stripped, then billing and membership redeployed with them, and
each deploy lane's smoke passed (the smoke retries over first-deploy
workers.dev route propagation — stack-tectonic ≥ 0.18.2, which the product's
`intent.yaml` pins).

## Troubleshooting

- **The phase refuses: `WIRING_*` missing** — phase 03 is incomplete; its
  two `verify` hooks assert the same keys. Re-run the phase 03 landing that
  owns the missing key (`WIRING_CLOUDFLARE_KV` → `03-infrastructure`,
  `WIRING_CLOUDFLARE_HYPERDRIVE` → `03-infrastructure-database`).
- **Cloudflare 10143 (service binding target not found)** during the FIRST
  landing — the strip did not cover an edge. From the product repo, run
  `node <baseline>/tooling/bootstrap/cycle-break.mjs --check` (it reads
  `apps/*/wrangler.template.jsonc` relative to the working directory); if a
  new feedback edge was introduced, add it to `FEEDBACK_EDGES`, kept in sync
  with `ACKNOWLEDGED_BINDING_CYCLES` in
  `tests/config-worker/src/deployment-config.test.ts`.
- **10143 during the restore** — a target worker never deployed in the first
  convergence. Resume that run before retrying the restore.
- **Convergence trips on runner starvation or resolve throttling** — that
  is what the auto-resume is for, and `max-parallel: 8` in `ci.yml` is
  deliberate. A genuinely red lane stays red across resumes: read its log.
- **Red after the resume budget** — re-running the phase lands nothing new,
  and CI plans `--changed`, so no push will redeploy what the failed run left
  undeployed. `gh run rerun --failed <run-id>` resumes the run itself; then
  re-run the phase so its `await` hook verifies. See
  [the phases README](README.md#pacing-idempotence-resume).

## Example commands

From the baseline checkout:

```bash
orun new --blueprint repo-blueprint.yaml --out $HOME/sourceplane/acme \
  --run-hooks --phase 04-workers \
  --values $HOME/sourceplane/acme/.rebrand/values.json

orun new --blueprint repo-blueprint.yaml --out $HOME/sourceplane/acme \
  --run-hooks --phase 04-workers-restore \
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
  --run-hooks --phase 04-workers --values /work/acme.values.yaml
orun new --blueprint repo-blueprint.yaml --out /work/acme \
  --run-hooks --phase 04-workers-restore --values /work/acme.values.yaml
```

Preview with zero side effects: drop `--run-hooks` — the phase places files
and stops, with no landing, no convergence watch and no probe. `--status`
derives every phase's state and writes nothing at all. Re-running a
completed phase is safe: the placement is a no-op, strip and restore are
idempotent, the landing finds nothing new, and the `await` hooks re-assert.

The pair measured ~31m end to end on the heaviest recorded run and ~21m on
a lighter one ([TIMINGS.md](TIMINGS.md)). A convergence that trips resumes
itself; a failed phase run resumes by re-running the same command with its
own `--phase`.

## Next

[Phase 05 — edge](05-edge.md).
