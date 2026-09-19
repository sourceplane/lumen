# Phase 05 — edge

Lands the **API edge** (`repo-blueprint.yaml`, phase `05-edge`) — the single
public entry point in front of the worker fleet — and proves it live.

## What it lands

- `apps/api-edge` (+ its test suite): the gateway worker, with service
  bindings to the ten fleet workers it fronts, the idempotency KV binding
  (namespace id from `WIRING_CLOUDFLARE_KV`) and the Hyperdrive binding
  (config id from `WIRING_CLOUDFLARE_HYPERDRIVE`), rendered per environment
  from `wrangler.template.jsonc`.
- `tests/platform-limits` — structural guards on the platform the fleet
  deploys under: account limits, the service-binding chain (it pins
  api-edge's chain depth), secret scoping. It reads every app and infra
  component, so it lands with the edge, the first phase at which the fleet
  it describes is whole.

**A live api-edge on both environments is proof the fleet exists.**
Cloudflare refuses an api-edge deploy while any worker it binds to is
missing, and those workers' own deploys were refused while anything THEY
bind to (policy-worker among them) was missing. The internal workers set
`workers_dev: false`, so this is otherwise unobservable from outside —
which is why this phase, not phase 04, carries the first probe. The one
worker it cannot vouch for is `admin-worker`, which nothing binds to; its
own deploy lane in phase 04 is the evidence for it.

## Inputs

`--out` is the product repo. The blueprint's required inputs — `reponame`,
`productname`, `productdomain`, `githuborg` — are validated before any phase
runs, so pass them on every invocation; the product's own
`.rebrand/values.json` is a complete values file. See
[the phases README](README.md#inputs).

## Steps

1. **requires** — `04-workers` placed. Not `04-workers-restore`: that phase
   places no files, derives as `unknown`, and a requirement on it could never
   be satisfied. Run the restore first anyway — `--resume` does.
2. **pre** — the phase's task.
3. **place** → **brand** → **lockfile** → **land** — the standard contract
   (PR `phase(05-edge): api-edge`).
4. **converge** — `orun.run/watch@v1` on the merged commit.
5. **verify** — an `orun.http/probe@v1` `await` hook probes
   `https://<reponame>-api-edge-{stage,prod}.<subdomain>.workers.dev/health`
   and fails on any dead endpoint. The URLs are templated from the
   blueprint's own inputs.

## Verify / done means

`/health` answers 2xx–4xx on BOTH environments. A 4xx is "alive but
unauthorized", which counts as deployed; a 5xx or a timeout does not.

## Troubleshooting

- **Deploy lane fails: `Service binding '<NAME>_WORKER' … not found`** — a
  fleet worker never deployed. This is how a partial phase 04 surfaces: the
  edge is the deploy that binds most of the fleet at once (it was
  `METERING_WORKER` the time it was found). Resume phase 04's failed
  convergence (`gh run rerun --failed <run-id>`), then re-run this phase.
- **`/health` unreachable on both environments after a green deploy** —
  check `subdomain` first. It must be the Cloudflare account's workers.dev
  subdomain; a wrong one deploys cleanly to URLs nobody can reach, and the
  probe is asking the wrong host.
- **`/health` 5xx after a green deploy** — the edge boots but a downstream
  binding misbehaves; check the worker it proxies to. The deploy lane's
  smoke already retried over route propagation, so this is real, not
  propagation.

## Example commands

From the baseline checkout:

```bash
orun new --blueprint repo-blueprint.yaml --out $HOME/sourceplane/acme \
  --run-hooks --phase 05-edge \
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
  --run-hooks --phase 05-edge --values /work/acme.values.yaml
```

Preview with zero side effects: drop `--run-hooks` — the phase places files
and stops, with no landing, no convergence watch and no probe. `--status`
derives every phase's state and writes nothing at all. Re-running a
completed phase is safe: the placement is a no-op, the landing finds
nothing new, and the `await` hooks re-probe.

On success the verify step has already probed
`https://acme-api-edge-{stage,prod}.<subdomain>.workers.dev/health`.

## Next

[Phase 06 — console](06-console.md).
