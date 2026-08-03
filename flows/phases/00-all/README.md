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

## Relationship to the phases

This is composition, not a parallel implementation: it invokes the same
`flows/phases/01…08` workflows, pinned to the SAME baseline commit the
umbrella was fetched from. Running phases individually (at your own
pace, re-running any of them) remains fully supported — see
[the phases README](../README.md).

## When it stops anyway

The failure output is the failing phase's own message, and the flows
print the exact operator action when one is needed (allow-list step,
admin-key re-mint, integration consent, billing-limit pointer). Fix the
named thing and re-run the SAME umbrella command — completed phases
no-op through in seconds.
