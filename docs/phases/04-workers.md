# Phase 04 — the worker fleet

Lands the **12-worker fleet** in ONE landing, and one convergence deploys it
on stage and prod with every service binding in place.

It used to be two landings: `04-workers` placed the fleet with two
service-binding feedback edges stripped out of its wrangler configs, and
`04-workers-restore` put them back once every target existed — two pull
requests, two convergences, the whole fleet deployed twice. That is gone;
see **Why one landing** below.

This is still the longest stretch of the bootstrap.

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

## Why one landing

The `{billing, membership, events, notifications}` cluster binds to itself —
billing ↔ membership, and membership → notifications → events → membership —
and a Cloudflare service binding cannot name a worker that does not exist
yet (error 10143). So on a fresh account no order of first deploys works:
something in the loop is always first.

`tooling/deploy/fleet-stubs.mjs` is the answer. `policy-worker` binds to
nothing, and every worker that holds a binding declares
`dependsOn: policy-worker` with `mode: enforced` (advisory on a pull
request, which deploys nothing). Its pre-deploy step reads every
`apps/*/wrangler{.template,}.jsonc` for the environment's
`services[].service` names and uploads a placeholder Worker — a module that
answers 503 — for each one that does not exist yet. Every real deploy then
starts with all its targets present, carries its FULL bindings, and replaces
its own placeholder.

It is race-free because nothing that holds a binding deploys while the
placeholders are being made: all of them wait on `policy-worker`. On a live
product every target exists and the tool uploads nothing. If the existence
check answers anything but 200 or 404 it refuses rather than guessing, so a
placeholder can never overwrite a real Worker.

`testing/fleet-stubs.test.sh` drives the tool against a fake Cloudflare API
— a fresh account, a half-built one, a live one, and an erroring one — and
checks that every binding holder in `apps/` waits on the worker whose
pre-deploy runs it.

## Inputs

`--out` is the product repo. The blueprint's required inputs — `reponame`,
`productname`, `githuborg` — are validated before any phase
runs, so pass them on every invocation; the product's own
`.rebrand/values.json` is a complete values file. See
[the phases README](README.md#inputs).

## What the phase does

1. **requires** — `03-infrastructure-database` placed. There is no wiring
   probe: `WIRING_CLOUDFLARE_KV` is what `03-infrastructure`'s own `verify`
   hook waited for and `WIRING_CLOUDFLARE_HYPERDRIVE` what
   `03-infrastructure-database`'s did, both immediately before this phase,
   and every worker resolves them from its `component.yaml` secret refs — so
   a missing document fails that worker's lane rather than passing silently.
2. **pre** — the phase's task. The run-level `hooks.preInstantiate` list
   opened it in the background before 01-scaffold placed a file; this finds
   it and yields its key.
3. **retouch** → **place** → **brand** → **lockfile**. `retouch` rewrites one
   trailing marker line in each component the task contract names, so a
   RE-RUN after a convergence that failed post-merge still has a diff to land
   (`tooling/bootstrap/retouch.mjs`).
4. **pen-reset** — clears this landing's own `orun/<task>-04-workers` branch
   if a stopped build left one behind, which would otherwise make every
   retry's push fail non-fast-forward (`tooling/bootstrap/pen-reset.mjs`).
5. **land** — PR `phase(04-workers): the worker fleet`, checked LOCALLY
   (`checks: local`): `orun validate` and both plans run on the commit before
   it is pushed, so a tree that fails is never pushed. The PR's CI runs
   `plan` alone on a bootstrap branch and nothing waits for it — the merge
   runs every lane on main a minute later, for real.
6. **converge** — the merge deploys the fleet, each worker with its full
   bindings. Budget an hour (`waitSeconds: 3600`), polled every 5 seconds,
   resumed up to three times. Lanes resolve their `WIRING_*` secrets at claim
   time. During a bootstrap stage and prod deploy side by side: 01-scaffold
   deferred prod's promotion gate and 08-docs puts it back.

## Verify / done means

One convergence run green: every worker deployed on stage and prod with its
full service bindings, and each deploy lane's smoke passed (the smoke retries
over first-deploy workers.dev route propagation, and a first deploy retries
Cloudflare's 10007 race — stack-tectonic ≥ 0.20.0, which the product's
`intent.yaml` pins).

## Troubleshooting

- **A worker's lane fails resolving `WIRING_*`** — phase 03 is incomplete;
  its two `verify` hooks assert the same keys. Re-run the phase 03 landing
  that owns the missing key (`WIRING_CLOUDFLARE_KV` → `03-infrastructure`,
  `WIRING_CLOUDFLARE_HYPERDRIVE` → `03-infrastructure-database`).
- **Cloudflare 10143 (service binding target not found)** — the worker does
  not wait on `policy-worker`, whose pre-deploy places every target. Check
  that its `dependsOn: policy-worker` carries `mode: enforced`;
  `testing/fleet-stubs.test.sh` asserts this for every binding holder. To see
  what would be placed: `node <baseline>/tooling/deploy/fleet-stubs.mjs
  --root . --env stage --list`.
- **Cloudflare 10007 (`This Worker does not exist on your account`)** — a
  first-deploy race. stack-tectonic ≥ 0.19.0 retries it; the watch hook's
  resume covers the rest.
- **The retry's push is rejected non-fast-forward** — a stopped build left
  the pen branch on the remote. The `pen-reset` hook clears it; if you are on
  an older baseline, `git push origin --delete orun/BASE-n-04-workers` and
  re-run the phase. Never `git pull` it: the branches have diverged.
- **Convergence trips on runner starvation or resolve throttling** — that is
  what the auto-resume is for, and `max-parallel: 19` in `ci.yml` is sized to
  the free plan's twenty concurrent jobs. A genuinely red lane stays red
  across resumes: read its log.
- **Red after the resume budget** — `gh run rerun --failed <run-id>` resumes
  the run itself; then re-run the phase so its `await` hook verifies. The
  `retouch` hook means the re-landing has a diff even when the merge already
  happened. See [the phases README](README.md#pacing-idempotence-resume).

## Example commands

From the baseline checkout:

```bash
orun new --blueprint repo-blueprint.yaml --out $HOME/sourceplane/acme \
  --run-hooks --phase 04-workers \
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
```

Preview with zero side effects: drop `--run-hooks` — the phase places files
and stops, with no landing, no convergence watch and no probe. `--status`
derives every phase's state and writes nothing at all. Re-running a
completed phase is safe: the placement is a no-op, the retouch marker is
idempotent, the landing finds nothing new, and the `await` hooks re-assert.

The pair measured ~31m end to end on the heaviest recorded run and ~21m on
a lighter one ([TIMINGS.md](TIMINGS.md)). A convergence that trips resumes
itself; a failed phase run resumes by re-running the same command with its
own `--phase`.

## Next

[Phase 05 — edge](05-edge.md).
