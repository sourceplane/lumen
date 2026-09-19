# Phase 08 — docs (record the live deployment)

Turns the freshly-live baseline into **documented, agent-readable state**:
renders the product's deployment manifest from PROBED facts rather than from
what the blueprint intended, and lands it on `main`. After this phase a
human — or an agent reading the repo through the Orun MCP surface — can
answer "what is deployed, where, and how do I operate it" from the
repository alone.

It places no modules. `ai/context/deployment.md` and
`ai/context/operations.md` were placed by `01-scaffold`; this phase's work
is a hook that rewrites them, a landing, and a probe.

## What it writes (in the product repo)

| file | content |
|---|---|
| `ai/context/deployment.md` | REGENERATED manifest: live URLs with probe results, workspace identity (id and slug), secrets inventory **by name only** per rung, integration statuses, the CI lane pin |
| `ai/context/operations.md` | the standing operating contract (architecture, tenancy resolution, deploy pipeline, secrets model, verification, troubleshooting). Healed from the baseline's copy when the product predates it; never rewritten after that |
| `README.md` | the section between `<!-- 08-docs:begin -->` / `<!-- 08-docs:end -->` markers is replaced (the section is inserted after the title for READMEs that predate the markers) |

No secret VALUE is ever read or written — inventories are names and
statuses. A credential that cannot list a rung yields "listing unavailable to
this credential" rather than a failed render.

## Steps

1. **requires** — `06-console` placed. Not `07-domain`, so a bootstrap that
   skips the custom domain still reaches this phase.
2. **pre** — the phase's task.
3. **render** — a `post` hook runs `hooks/render-deployment-docs.sh . <workspace>
   <baseline-dir>` from the baseline checkout. It reads identity from
   `.rebrand/values.json`, probes the four public URLs (and
   `api.<productdomain>/health` and `app.<productdomain>`, reported as
   pending when they do not answer), lists secrets and integrations by name
   with `orun secrets list` / `orun integrations list`, and renders the files
   above. It refuses to finish if a `TBD_08DOCS` placeholder survives.
4. **land** — `orun.pr/land@v1`: PR `docs(deployment): record live
   deployment state`. A docs-only landing plans ZERO deploy lanes, so this
   phase has no convergence to watch — it is the one phase whose `await` is
   a probe alone.
5. **verify** — an `orun.http/probe@v1` `await` hook re-probes the four URLs
   the manifest claims, trusting nothing the render step said about them.

## When to run (and re-run)

- Right after [phase 06](06-console.md) — the "working baseline" moment —
  to record it.
- Again after [phase 07](07-domain.md), once the domain actually resolves,
  so the manifest picks up the custom-domain URLs.
- Any time later as a **live-state refresh**: the manifest is regenerated
  from scratch on every run and carries its own render timestamp. The
  product's `ai/context/operations.md` carries the same command for its own
  operators.

## Inputs

`--out` is the product repo. The blueprint's required inputs — `reponame`,
`productname`, `productdomain`, `githuborg` — are validated before any phase
runs, so pass them on every invocation; the product's own
`.rebrand/values.json` is a complete values file. The renderer also takes
`orunWorkspace`, which that file records. See
[the phases README](README.md#inputs).

## Example commands

From the baseline checkout:

```bash
orun new --blueprint repo-blueprint.yaml --out $HOME/sourceplane/acme \
  --run-hooks --phase 08-docs \
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
  --run-hooks --phase 08-docs --values /work/acme.values.yaml
```

Without `--run-hooks` this phase does nothing at all: it places no files,
and the render, the landing and the probe are all hooks. The renderer is
also safe to run by hand against a product checkout (`bash
hooks/render-deployment-docs.sh <out> <workspace> <baseline-dir>`): it
rewrites the three files in that tree and lands nothing, so `git diff`
there shows what the phase would land.

## Troubleshooting

- **verify fails on a URL** — the manifest is honest: something the docs
  would claim live is not. Re-run phase 05's or 06's verify to localize it.
- **secrets/integrations listed as "unavailable to this credential"** — the
  runner's token cannot list that rung; the manifest still renders (URLs and
  identity are the load-bearing parts). Re-run with a fuller-scoped
  credential to enrich it.
- **`placeholder tokens remain`** — a `TBD_08DOCS` survived the render in
  `ai/context/` or `README.md`; the message lists where. The render refuses
  rather than landing a half-filled manifest.
- **The workspace slug shows as `?`** — `orun workspace <ws>` could not be
  read with this credential. Cosmetic; the id is still recorded.
