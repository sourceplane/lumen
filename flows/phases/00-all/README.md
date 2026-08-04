# Phase 00 — the umbrella (nothing → live, documented, unattended)

ONE workflow that runs the whole bootstrap: scaffold → foundation →
infrastructure → workers → edge → console → (optional domain) → docs →
final verification. No agent, no babysitting — every phase is invoked
with retry, waits are built into the phases themselves, and the last
step independently re-asserts the outcome.

```bash
# headless (any container; ADMIN-role ORUN_TOKEN + GITHUB_TOKEN exported):
orun workflow run github:sourceplane/lumen@<tag>//flows/phases/00-all/workflow.yaml \
  --set workspace=ws_ABCD1234 --set reponame=acme \
  --set productname="Acme Cloud" --set productdomain=acme.dev \
  --set subdomain=<workers-dev-subdomain>

# local mode: same from this checkout, plus --set out=<product-path>
```

Expected wall-clock on a clean run: **~60–75 minutes** (Supabase
provisioning and the two worker landings dominate).

## Why this can run unattended

- **Retry over idempotent phases**: each phase self-heals its own crash
  debris (inflight-marker reset), landings/converge fall back to plain
  REST when `gh` is degraded, smokes retry route propagation (~4.5 m),
  OCI resolves retry transient 5xx, and convergence auto-resumes failed
  lanes ×3. The umbrella re-runs a failed phase (backoff 60 s·attempt):
  transient trouble clears; a real problem fails every attempt and stops
  with the phase's own actionable message.
- **It resumes instead of restarting** — see below. A failed run picks up
  at the failed phase, not at phase 01.
- **The expensive failure moved to minute two**: right after the
  scaffold, `credprobe` runs `create-secrets.sh` — the first real WRITE.
  A read-only (sub-admin) key dies HERE with the re-mint-as-admin hint,
  not thirty minutes in at phase 03. It is idempotent: phase 03 later
  finds every secret "kept".
- **Verification is independent**: the final step re-probes all four
  URLs, re-lists the published `WIRING_*`/`SUPABASE_*` secrets on both
  environments, and re-checks the committed docs manifest — trusting no
  earlier step's word.

## What still needs a human (once, up front)

1. Workspace integrations connected (GitHub + Cloudflare + Supabase) —
   preflight polls 10 minutes so consents can be clicked while it waits.
2. The product repo allow-listed (console → Settings → Git repos) — the
   one console action no token can self-heal. Do it before starting, or
   the first preflight stops and names exactly this step.
3. An **admin-role** API key (builder/viewer keys fail the credprobe with
   the exact fix in the message).

## Inputs

| input | default | notes |
|---|---|---|
| `workspace` | — | ws_… id or slug |
| `reponame` / `productname` / `productdomain` / `subdomain` | — | identity, passed to phase 01 |
| `githuborg` | `sourceplane` | |
| `out` | `./product` | product path (local mode) |
| `domain` | `false` | `true` also runs phase 07 (zone must exist) |
| `watch` | `true` | `false` skips convergence WATCHING everywhere (env cannot see Actions); verify runs out-of-band |
| `dryrun` | `false` | previews the scaffold, then stops |
| `from` | `""` | resume point: skip every phase before this one |
| `fresh` | `false` | `true` clears the checkpoint and runs every phase again |

## Relationship to the phases

This is composition, not a parallel implementation: it invokes the same
`flows/phases/01…08` workflows, pinned to the SAME baseline commit the
umbrella was fetched from. Running phases individually (at your own
pace, re-running any of them) remains fully supported — see
[the phases README](../README.md).

## When it stops anyway — resuming

The failure output is the failing phase's own message, and the flows
print the exact operator action when one is needed (allow-list step,
admin-key re-mint, integration consent, billing-limit pointer). Fix the
named thing and **re-run the same umbrella command**: it resumes at the
failed phase.

How the resume point is established, in order:

1. **Checkpoint** — `<workdir>/.orun-bootstrap/state`, written after each
   phase. Fast, and exact, when the workdir survived.
2. **Reality probes** — when there is no checkpoint (a fresh headless
   container, the usual case), each phase is asked whether its
   *observable postcondition* holds: repo content on `main`, the
   published `WIRING_*`/`SUPABASE_*` secrets, live endpoints. Reality
   survives container death; a state file does not.

Probes are deliberately conservative — when one cannot tell, it says
"not done" and the phase re-runs. Re-running a genuinely finished phase
costs time; *skipping* an unfinished one costs a broken product.

Two overrides:

| flag | effect |
|---|---|
| `--set from=05-edge` | skip everything before that phase, whatever the checkpoint says |
| `--set fresh=true` | clear the checkpoint and run every phase again |

### Why a resume also forces redeploys

Git-level idempotence is **not** deploy-level idempotence. The product's
CI plans with `orun plan --changed`, so a component deploys only when its
files changed in the push. After a failed convergence the content is
already on `main` and the deploy never happened — so re-applying the same
content produces an *empty* plan and the component is never deployed, no
matter how many times you restart.

Retries therefore stamp a `# ci: <reason>` line on the phase's
`component.yaml` files (`flows/common/redeploy-marker.sh`), putting them
back in the changed set. Deploys are upserts, so re-deploying a live
component is a no-op that costs only CI time.

This is not hypothetical: a product bootstrapped before this existed took
three full umbrella restarts and never deployed six of its twelve
workers. Phase 05 only surfaced it when api-edge's own deploy failed with
`Service binding 'METERING_WORKER' … not found`. That failure is also the
invariant phase 04's probe leans on — Cloudflare refuses an api-edge
deploy while any bound worker is missing, so **a live api-edge on both
environments is proof the whole fleet exists**, which is otherwise
unobservable (internal workers set `workers_dev: false`).
