# Phase 06 — console

Lands the **web console** (`repo-blueprint.yaml`, phase `06-console`) — the
product UI served from Workers static assets — and proves both it and the
edge it talks to live.

## What it lands

`apps/web-console-next` (+ its test suite): the Next.js console, built and
deployed as a Cloudflare worker with static assets, configured against the
phase 05 edge. Console builds are the heaviest lane in the product, which is
why this phase's landing waits up to 45 minutes for its PR and its
convergence watch up to 45 minutes too.

## Inputs

`--out` is the product repo. The blueprint's required inputs — `reponame`,
`productname`, `productdomain`, `githuborg` — are validated before any phase
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

[Phase 08 — docs](08-docs.md) records what was built. Optional
[phase 07 — domain](07-domain.md) comes first only if you set
`domain=true` — read that page before you do.

Post-baseline: seed runtime worker secrets (`orun secrets set <KEY> --org
<ws> --env <env>`; wire-now-seed-later, nothing blocks on them) and ship
normal PRs.
