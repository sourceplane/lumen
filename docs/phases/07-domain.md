# Phase 07 — domain (OPTIONAL, and not yet wired end to end)

Lands the **custom product domain** (`repo-blueprint.yaml`, phase
`07-domain`): the `cloudflare-domain` terraform that is meant to put the
console on `<productdomain>` instead of workers.dev.

Skip it until you own the domain — the baseline is fully functional on
workers.dev URLs after phase 06. And read the next section before you run it
at all.

## What this phase does today — read this first

In this baseline, running `07-domain` lands the component and **deploys
nothing**, for two reasons that live in the component rather than in the
phase:

1. **`cloudflare-domain` ships parked.** Its `component.yaml` declares
   `subscribe.environments: []`, so CI plans no lanes for it. The phase's
   convergence is therefore a run with nothing in it, and reads green. This
   is the "a green run that deployed nothing" trap every other phase guards
   against with a probe; this phase has no probe to catch it.
2. **The custom-domain attachment is fenced off.** The component is midway
   through a two-step migration to Cloudflare provider v5: the v4
   `cloudflare_workers_domain` resource was dropped from state and its
   block is commented out until the v5 `cloudflare_workers_custom_domain`
   replaces it. Un-parked as it stands, the root would look up the zone and
   attach nothing.

So the honest status is: the phase, its task and its PR work; the domain
does not. Wiring it for real means, in the product, finishing the v5
resource and restoring the `subscribe` block (both are described in the
component's own comments), then landing that as a normal PR once the zone
exists. The phase's narration says the domain resolves when it is done —
it does not, yet.

## Prerequisite (hard)

The product zone (e.g. `acme.dev`) must **already exist in the Cloudflare
account** — created in the dashboard; zone creation is an account-plan
operation the platform does not broker. The component runs with
`zoneMode: existing`: it looks the zone up by `baseDomain` and manages
records and custom domains IN it, not the zone itself. Without the zone a
plan fails with `no zone found`.

## What it lands

`infra/terraform/cloudflare-domain`: the zone lookup and, once the migration
above is finished, a custom domain per environment for the console worker —
`CONSOLE_CUSTOM_DOMAIN` in the product's `intent.yaml`,
`stage.<productdomain>` and `prod.<productdomain>` after rebrand (empty for
`dev`).

## Inputs

`--out` is the product repo. The blueprint's required inputs — `reponame`,
`productname`, `productdomain`, `githuborg` — are validated before any phase
runs, so pass them on every invocation; the product's own
`.rebrand/values.json` is a complete values file. See
[the phases README](README.md#inputs).

The phase carries `when: inputs.domain`, so it is **skipped** unless
`domain=true` — set on the command line or recorded in the values file. A
skipped phase does not block `08-docs`, which requires `06-console` rather
than this one. The console card collects no `domain`, so a console build
always skips this phase.

## Steps

1. **requires** — `06-console` placed.
2. **pre** — the phase's task (its milestone is ensured only on a run that
   asks for the phase).
3. **place** → **brand** → **lockfile** → **land** — the standard contract
   (PR `phase(07-domain): custom domain`).
4. **converge** — `orun.run/watch@v1` on the merged commit. See above for
   what that run contains today.

## Verify / done means

The convergence run is green. Then — once the component is wired — check the
product resolves on its own domain (DNS propagation applies), and re-run
[phase 08](08-docs.md) so the deployment manifest records the custom-domain
URLs.

## Troubleshooting

- **Plan fails: zone not found** — the zone does not exist in this
  Cloudflare account yet, or the brokered token's account differs from the
  zone's account. Create the zone, re-run.
- **Green convergence, domain does not resolve** — expected today; see
  "What this phase does today".

## Example commands

From the baseline checkout:

```bash
orun new --blueprint repo-blueprint.yaml --out $HOME/sourceplane/acme \
  --run-hooks --phase 07-domain --set domain=true \
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
  --run-hooks --phase 07-domain --set domain=true --values /work/acme.values.yaml
```

Preview with zero side effects: drop `--run-hooks` — the phase places files
and stops, with no landing, no convergence watch and no probe. `--status`
derives every phase's state and writes nothing at all.

## Next

[Phase 08 — docs](08-docs.md).
