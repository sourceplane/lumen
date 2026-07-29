# Phase 07 — domain (OPTIONAL)

Lands the **custom product domain** (`flows/phases/07-domain/blueprint.yaml`): DNS +
routing terraform that puts the product on `<productdomain>` instead of
workers.dev.

Skip it entirely until you own the domain — the baseline is fully
functional on workers.dev URLs after phase 06.

## Prerequisite (hard)

The product zone (e.g. `acme.dev`) must **already exist in the Cloudflare
account** — created manually in the dashboard (zone creation is an
account-plan operation the platform does not broker). The terraform here
manages records/routes IN the zone, not the zone itself. Without the zone
the apply fails at plan.

## What it lands

`infra/terraform/cloudflare-domain`: the `cloudflare-domain` component
(records, worker routes/custom domains for edge + console per
environment).

## Inputs

`out`, `workspace`, optional `dryrun` (see [the phases README](../README.md)).

## Steps

1. **preflight** — workspace readiness.
2. **apply** → **land** → **converge** — the standard contract
   (PR `phase(07-domain): custom domain`).

## Verify / done means

The convergence run is green. Then check the product resolves on its own
domain (DNS propagation applies).

## Troubleshooting

- **Plan fails: zone not found** — the zone does not exist in this
  Cloudflare account yet, or the brokered token's account differs from the
  zone's account. Create the zone, re-run.
- **Express-flow users**: in the single-run path this component ships
  PARKED for exactly this reason; un-parking it there
  (`node flows/common/park.mjs unpark cloudflare-domain`) is the
  equivalent of running this phase.
