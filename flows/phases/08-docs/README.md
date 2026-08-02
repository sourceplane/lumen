# Phase 08 — docs (record the live deployment)

Turns the freshly-live baseline into **documented, agent-readable state**:
renders the product's deployment manifest from VERIFIED facts and lands it
on main. After this phase, a human — or an agent reading the repo through
the Orun MCP surface — can answer "what is deployed, where, and how do I
operate it" from the repository alone.

## What it writes (in the product repo)

| file | content |
|---|---|
| `ai/context/deployment.md` | REGENERATED manifest: live URLs with probe results, workspace/project identity, secrets inventory **by name only**, integration statuses, baseline provenance, CI lane pin |
| `ai/context/operations.md` | the standing operating contract (architecture, tenancy resolution, deploy pipeline, secrets model, verification, troubleshooting). Healed from the baseline template when the product predates it; never rewritten after that |
| `README.md` | the section between `<!-- 08-docs:begin -->` / `<!-- 08-docs:end -->` markers is replaced (markers are appended for READMEs that predate them) |

No secret VALUE is ever read or written — inventories are names/statuses.

## Steps

1. **preflight** — workspace readiness (same gate as every phase).
2. **docs** — `common/render-deployment-docs.sh`: probes the four public
   URLs (plus the custom domain when `productDomain` is set), lists
   secrets/integrations by name, renders the files above.
3. **land** — `common/push-main.sh`: a docs-only push plans ZERO deploy
   lanes, so there is no convergence to watch.
4. **verify** — asserts no `TBD_08DOCS` placeholder survived **in the
   committed tree**, the manifest is on main, and the URLs it claims are
   actually live (`verify-endpoints.sh edge console`).

## When to run (and re-run)

- Right after [phase 06](../06-console/README.md) — the "working baseline"
  moment — to record it.
- Again after [phase 07](../07-domain/README.md) so the manifest picks up
  the custom-domain URLs.
- Any time later as a **live-state refresh**: it is fully idempotent; the
  manifest is regenerated from scratch on every run and carries its own
  render timestamp.

## Inputs

`out`, `workspace`, optional `dryrun` (see [the phases README](../README.md)).

## Example commands

From the baseline checkout (local mode):

```bash
orun workflow run flows/phases/08-docs/workflow.yaml \
  --set out=$HOME/sourceplane/acme --set workspace=ws_ABCD1234
```

Headless (fresh container / no checkout — see BOOTSTRAP.md §3c): same
command by remote reference, with `ORUN_TOKEN` + `GITHUB_TOKEN` exported
and `--set repo=<owner/name>` instead of `out`:

```bash
orun workflow run github:sourceplane/lumen@main//flows/phases/08-docs/workflow.yaml \
  --set workspace=ws_ABCD1234 --set repo=sourceplane/acme
```

Preview with zero side effects (either mode): append `--set dryrun=true` —
docs are rendered, the diff is shown, and everything is reverted; nothing
is pushed.

## Troubleshooting

- **verify fails on a URL** — the manifest is honest: something the docs
  would claim live is not. Re-run phase 05/06's verify to localize.
- **secrets/integrations listed as "unavailable to this credential"** —
  the runner's token cannot list that rung; the manifest still renders
  (URLs and identity are the load-bearing parts). Re-run with a
  fuller-scoped credential to enrich it.
