# Phase 06 — console

Lands the **web console** (`repo-blueprint.yaml`, phase `06-console`) — the
product UI served from Workers static assets — and proves both it and the
edge it talks to live. The custom-domain component lands with it, parked
([below](#the-custom-domain--parked)).

## What it lands

`apps/web-console-next` (+ its test suite): the Next.js console, built and
deployed as a Cloudflare worker with static assets, configured against the
phase 05 edge. Console builds are the heaviest lane in the product, which is
why this phase's landing waits up to 45 minutes for its PR and its
convergence watch up to 45 minutes too.

`infra/terraform/cloudflare-domain` lands in the same pull request, parked.
`testing/phases.test.sh` holds the set: modules move whole, and nothing else
moves with them.

## The custom domain — parked

`infra/terraform/cloudflare-domain` — the zone lookup and, once wired, a
custom domain per environment for the console worker
(`CONSOLE_CUSTOM_DOMAIN` in the product's `intent.yaml`:
`stage.<productdomain>` and `prod.<productdomain>` after rebrand, empty for
`dev` — and, since the console asks for no domain, `<productdomain>` is the
placeholder `<reponame>.example.com` until an owner sets one) — lands with
the console and **deploys nothing**, for two reasons that live in the
component rather than in the phase:

1. **It ships parked.** Its `component.yaml` declares
   `subscribe.environments: []`, so CI plans no lanes for it. The product
   runs on workers.dev URLs until an owner wires it.
2. **The attachment is fenced off.** The component is midway through a
   two-step migration to Cloudflare provider v5: the v4
   `cloudflare_workers_domain` resource was dropped from state and its block
   is commented out until the v5 `cloudflare_workers_custom_domain` replaces
   it. Un-parked as it stands, the root would look up the zone and attach
   nothing.

It used to land on its own as the optional `07-domain` phase, behind a
`domain` input. That landing deployed nothing either — its convergence was a
green run with nothing in it — so the phase and the switch are gone, and
this phase's task contract leaves the component out of `affects`: there is
nothing in it to re-plan.

Wiring it is a normal pull request in the product, once the zone exists.
The product's `ai/context/operations.md` ("Setting the domain later") carries
the whole list for its owner: replace the placeholder everywhere it stands
(`git grep -l <reponame>.example.com` — intent, the edge and identity console
origins, the mail sender, the billing return URLs), then:

1. **The zone first.** The product zone (e.g. `acme.dev`) must already exist
   in the Cloudflare account the product deploys into, created in the
   dashboard; zone creation is an account-plan operation the platform does
   not broker. The component runs with `zoneMode: existing`: it looks the
   zone up by `baseDomain` and manages records and custom domains IN it, not
   the zone itself. Without the zone a plan fails with `no zone found` (or
   the brokered token's account is not the zone's).
2. **Finish the v5 resource and restore the `subscribe` block** the
   component carries commented out — both are described in its own comments,
   and its `README.md` says where the migration stands.
3. **Land it.** The convergence on `main` applies it; check the product
   resolves on its own domain (DNS propagation applies), then re-run
   [`08-docs`](08-docs.md) so the deployment manifest records the
   custom-domain URLs.

## Inputs

`--out` is the product repo. The blueprint's required inputs — `reponame`,
`productname`, `githuborg` — are validated before any phase
runs, so pass them on every invocation; the product's own
`.rebrand/values.json` is a complete values file. See
[the phases README](README.md#inputs).

## Steps

1. **requires** — `05-edge` placed.
2. **pre** — the phase's task.
3. **place** → **brand** → **lockfile** → **land** — the standard contract
   (PR `phase(06-console): web console`).
4. **converge** — `orun.run/watch@v1` on the merged commit.
5. **verify** — an `orun.http/probe@v1` `await` hook: the console roots AND
   the edge `/health`, on stage and prod.

## Verify / done means

All four URLs answer:
`https://<reponame>-web-console-next-{stage,prod}.<subdomain>.workers.dev`
plus the two edge health endpoints. **This is the "working baseline"
moment** — after this phase the product is live end to end.

## Troubleshooting

- **Smoke fails right after the very first deploy** — a brand-new workers.dev
  route can 4xx for a few seconds; the deploy lane's smoke already retries
  over that. A persistent failure is real: check the console's build output
  in the lane log.
- **The convergence needs its resumes** — on the heaviest measured run the
  console's convergence used all three and healed itself; on the next it
  used none. Resumes spent here are not a regression by themselves.
- **Console up, edge probes fail** — re-run `05-edge`; the console is static
  assets and can be "up" while the API behind it is not.

## Example commands

From the baseline checkout:

```bash
orun new --blueprint repo-blueprint.yaml --out $HOME/sourceplane/acme \
  --run-hooks --phase 06-console \
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
  --run-hooks --phase 06-console --values /work/acme.values.yaml
```

Preview with zero side effects: drop `--run-hooks` — the phase places files
and stops, with no landing, no convergence watch and no probe. `--status`
derives every phase's state and writes nothing at all. Re-running a
completed phase is safe: the placement is a no-op, the landing finds
nothing new, and the `await` hooks re-probe.

## Next

[Phase 08 — docs](08-docs.md) records what was built. The custom domain is
wired later, in an ordinary PR ([above](#the-custom-domain--parked)).

Post-baseline: seed runtime worker secrets (`orun secrets set <KEY> --org
<ws> --env <env>`; wire-now-seed-later, nothing blocks on them) and ship
normal PRs.
