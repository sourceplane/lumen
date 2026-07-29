# Phase 04 — workers

Lands the **12-worker fleet** (`flows/phases/04-workers/blueprint.yaml`) in two
landings: first with the service-binding feedback edges stripped so
first-boot workers can deploy in DAG order, then a restore landing once
every worker they point at exists.

## What it lands

`apps/`: `policy-worker`, `membership-worker`, `events-worker`,
`projects-worker`, `identity-worker`, `config-worker`, `webhooks-worker`,
`notifications-worker`, `metering-worker`, `admin-worker`,
`billing-worker`, `integrations-worker` — plus their test components.
Each worker's deploy renders its committed `wrangler.template.jsonc`
(`@@wiring(...)@@` tokens) from the `WIRING_*` secrets phase 03 published,
and reads its own runtime keys wire-now-seed-later (inert until seeded).

## Why two landings

`billing → membership → notifications` form acknowledged service-binding
feedback edges: deploying any of them first-boot with the binding present
fails (the target worker does not exist yet, Cloudflare error 10143).
`tooling/bootstrap/cycle-break.mjs`:

- `--strip` removes exactly those edges (byte-preserving markers) before
  the first landing — the fleet deploys clean in DAG order;
- `--restore` puts them back byte-for-byte for the second landing, when
  every target exists.

Both are idempotent; `--check` reports the current state.

## Inputs

`out`, `workspace`, optional `dryrun` (see [the phases README](../README.md)).

## Steps

1. **preflight** — workspace readiness (fast when healthy).
2. **apply** — blueprint slice + rebrand, then `cycle-break --strip`.
3. **land** — PR `phase(04-workers): worker fleet (feedback edges
   stripped)`; the PR's verify lanes are plan/build-only.
4. **converge** — the merge deploys the fleet (longest phase; budget 90m,
   auto-resumed). Lanes resolve their `WIRING_*`/`SUPABASE_*` secrets at
   claim time — missing keys here mean phase 03 did not finish.
5. **restore** — `cycle-break --restore`, second PR, second convergence.

## Verify / done means

Both convergence runs green: every worker deployed twice (stripped, then
with full bindings) and its smoke passed (smoke retries ~75s over
first-deploy workers.dev propagation — stack-tectonic ≥ 0.18.1).

## Troubleshooting

- **Lane fails resolving `WIRING_*`**: phase 03 incomplete — its verify
  asserts these; re-run phase 03.
- **Cloudflare 10143 (service binding target not found)** during the
  FIRST landing: the strip did not cover an edge — `node
  tooling/bootstrap/cycle-break.mjs --check` in the product repo; if a new
  feedback edge was introduced, add it to `FEEDBACK_EDGES` (kept in sync
  with the acknowledged-cycles test).
- **Convergence trips on runner starvation / resolve throttling**: that is
  what the auto-resume is for; a genuinely red lane stays red across
  resumes — read that lane's log.

## Next

[Phase 05 — edge](../05-edge/README.md).
