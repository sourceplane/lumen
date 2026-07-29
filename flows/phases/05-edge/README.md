# Phase 05 — edge

Lands the **API edge** (`flows/phases/05-edge/blueprint.yaml`) — the single public
entry point fronting the worker fleet — and proves it live.

## What it lands

`apps/api-edge` (+ its test component): the gateway worker with service
bindings to the fleet from phase 04, the idempotency KV binding (id from
`WIRING_CLOUDFLARE_KV`), and the Hyperdrive binding (id from
`WIRING_CLOUDFLARE_HYPERDRIVE`).

## Inputs

`out`, `workspace`, optional `dryrun` (see [the phases README](../README.md)).

## Steps

1. **preflight** — workspace readiness.
2. **apply** → **land** → **converge** — the standard contract
   (PR `phase(05-edge): api-edge`).
3. **verify** — `common/verify-endpoints.sh <out> edge` probes
   `https://<repo>-api-edge-{stage,prod}.<subdomain>.workers.dev/health`
   and fails on any dead endpoint (URLs derived from
   `.rebrand/values.json`).

## Verify / done means

`/health` answers 2xx–4xx (a 4xx is "alive but unauthorized", which counts
as deployed; 5xx/timeout does not) on BOTH environments.

## Troubleshooting

- **Deploy lane fails on a missing service binding**: phase 04's restore
  landing did not complete — its second convergence must be green first.
- **`/health` 5xx after a green deploy**: the edge boots but a downstream
  binding misbehaves — check the worker it proxies to; the smoke in the
  deploy lane retried ~75s already, so this is real, not propagation.

## Next

[Phase 06 — console](../06-console/README.md).
