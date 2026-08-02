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
domain (DNS propagation applies). Re-run
[phase 08](../08-docs/README.md) afterwards so the deployment manifest
records the custom-domain URLs.

## Troubleshooting

- **Plan fails: zone not found** — the zone does not exist in this
  Cloudflare account yet, or the brokered token's account differs from the
  zone's account. Create the zone, re-run.
- **Express-flow users**: in the single-run path this component ships
  PARKED for exactly this reason; un-parking it there
  (`node flows/common/park.mjs unpark cloudflare-domain`) is the
  equivalent of running this phase.

## Example commands

From the baseline checkout (local mode):

```bash
orun workflow run flows/phases/07-domain/workflow.yaml \
  --set out=$HOME/sourceplane/acme --set workspace=ws_ABCD1234
```

Headless (fresh container / no checkout — see BOOTSTRAP.md §3c): same
command by remote reference, with `ORUN_TOKEN` + `GITHUB_TOKEN` exported
and `--set repo=<owner/name>` instead of `out`:

```bash
export ORUN_TOKEN="$(orun auth token | tail -1)" GITHUB_TOKEN=…
orun workflow run github:sourceplane/lumen@main//flows/phases/07-domain/workflow.yaml \
  --set workspace=ws_ABCD1234 --set repo=sourceplane/acme
```

Preview with zero side effects (either mode): append `--set dryrun=true` —
the blueprint is applied, shown, and reverted; nothing is pushed or
deployed. Re-running a completed phase is always safe (idempotent): the
apply is a no-op, the landing finds nothing, and verify re-asserts.

Run ONLY after the product zone (e.g. `acme.dev`) exists in the Cloudflare
account — the apply fails at plan without it.
