# Phase 06 — console

Lands the **web console** (`flows/phases/06-console/blueprint.yaml`) — the product UI
served from Workers assets — and proves both it and the edge it talks to
live.

## What it lands

`apps/web-console-next` (+ its test component): the Next.js console built
and deployed as a Cloudflare worker with static assets, configured against
the phase 05 edge.

## Inputs

`out`, `workspace`, optional `dryrun` (see [the phases README](../README.md)).

## Steps

1. **preflight** — workspace readiness.
2. **apply** → **land** → **converge** — the standard contract
   (PR `phase(06-console): web console`).
3. **verify** — `common/verify-endpoints.sh <out> edge console`: the
   console roots AND the edge `/health`, on stage and prod.

## Verify / done means

All four URLs answer:
`https://<repo>-web-console-next-{stage,prod}.<subdomain>.workers.dev`
plus the edge health endpoints. **This is the "working baseline" moment**
— after this phase the product is live end-to-end.

## Troubleshooting

- **Smoke fails right after the very first deploy**: a brand-new
  workers.dev route can 4xx for a few seconds — the deploy lane's smoke
  already retries ~75s (stack-tectonic ≥ 0.18.1); a persistent failure is
  real. Check the console's build output in the lane log.
- **Console up, edge probes fail**: run phase 05's verify again; the
  console is static assets and can be "up" while the API behind it is not.

## Next

Optional [Phase 07 — domain](../07-domain/README.md), or stop here — the
baseline is live. Post-baseline: seed runtime worker secrets
(`orun secrets set <KEY> --org <ws> --env <env>`; wire-now-seed-later,
nothing blocks on them) and ship normal PRs.
