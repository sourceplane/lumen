#!/usr/bin/env bash
# Render the product's LIVE-DEPLOYMENT documentation from verified state.
# Called by flows/phases/08-docs (and safe to run by hand). Idempotent: the
# generated files and the README section are fully re-rendered on every run,
# so re-running after phase 07 (custom domain) or any redeploy refreshes them.
#
#   flows/common/render-deployment-docs.sh <out> <workspace> <baseline-dir>
#
# What it writes (in <out>):
#   ai/context/deployment.md   — REGENERATED: the deployment manifest (URLs
#                                with live probe results, identity, secrets
#                                inventory BY NAME, integrations, provenance)
#   ai/context/operations.md   — healed from the baseline template if absent
#                                (static operator/agent guide; never rewritten)
#   README.md                  — the section between <!-- 08-docs:begin/end -->
#                                markers is replaced (markers appended if the
#                                README predates them)
#
# No secret VALUE is ever read or written here — inventories are names only.
set -euo pipefail

out="${1:?usage: render-deployment-docs.sh <out> <workspace> <baseline-dir>}"
ws="${2:?usage: render-deployment-docs.sh <out> <workspace> <baseline-dir>}"
L="${3:?usage: render-deployment-docs.sh <out> <workspace> <baseline-dir>}"

cd "$out"
vals=".rebrand/values.json"
[ -f "$vals" ] || { echo "render-docs: $vals missing — is this a scaffolded product?" >&2; exit 1; }

repo="$(python3 -c "import json;print(json.load(open('$vals'))['repoName'])")"
sub="$(python3 -c "import json;print(json.load(open('$vals'))['workersDevSubdomain'])")"
domain="$(python3 -c "import json;print(json.load(open('$vals')).get('productDomain',''))")"

# Workspace slug via the direct backend read (works for user sessions AND
# workspace-scoped ORUN_TOKENs); tolerate failure — slug then shows as "?".
slug="$( { orun workspace "$ws" 2>/dev/null || true; } | sed -n 's/^ *slug: *//p' | head -1)"
[ -n "$slug" ] || slug="?"

# CI lane pin (what version the deploy lanes run).
lanepin="$(sed -n 's/^ *version: *\(v[0-9.]*\) *$/\1/p' .github/workflows/ci.yml 2>/dev/null | head -1)"
[ -n "$lanepin" ] || lanepin="?"

# Baseline provenance: the pinned source this flow (and the docs) came from.
bsrc="${ORUN_FLOW_SOURCE_REPO:-sourceplane/lumen}@${ORUN_FLOW_SOURCE_SHA:-${ORUN_FLOW_SOURCE_REF:-main}}"

# curl emits the -w format even on connection failure (000) — capture, don't
# append, or a failed probe reads "000000".
probe() { local c; c="$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 "$1" 2>/dev/null)" || true; printf '%s' "${c:-000}"; }
badge() { case "$1" in 2*|3*|401|403) echo "LIVE ($1)" ;; 000) echo "unreachable" ;; *) echo "answering $1" ;; esac; }

edge_stage="https://${repo}-api-edge-stage.${sub}.workers.dev"
edge_prod="https://${repo}-api-edge-prod.${sub}.workers.dev"
con_stage="https://${repo}-web-console-next-stage.${sub}.workers.dev"
con_prod="https://${repo}-web-console-next-prod.${sub}.workers.dev"

p_es="$(probe "$edge_stage/health")"; p_ep="$(probe "$edge_prod/health")"
p_cs="$(probe "$con_stage")";        p_cp="$(probe "$con_prod")"

# Custom domain (phase 07, optional): probe only if a domain is declared;
# an unreachable domain is reported as pending, never a failure.
dom_rows=""
if [ -n "$domain" ]; then
  p_da="$(probe "https://api.${domain}/health")"
  p_dc="$(probe "https://app.${domain}")"
  dom_rows="| edge (custom domain) | https://api.${domain}/health | $( [ "$p_da" = 000 ] && echo 'pending (phase 07 not run, or DNS propagating)' || badge "$p_da" ) |
| console (custom domain) | https://app.${domain} | $( [ "$p_dc" = 000 ] && echo 'pending (phase 07 not run, or DNS propagating)' || badge "$p_dc" ) |"
fi

# Inventories — NAMES/status only, never values. Tolerant: a token that
# cannot list simply yields an "unavailable" note instead of failing docs.
secrets_proj="$( { orun secrets list --org "$ws" --project 2>/dev/null || true; } | awk 'NR>1 && NF {print "  - "$1}' )"
secrets_stage="$( { orun secrets list --org "$ws" --env stage 2>/dev/null || true; } | awk 'NR>1 && NF {print "  - "$1}' )"
secrets_prod="$( { orun secrets list --org "$ws" --env prod 2>/dev/null || true; } | awk 'NR>1 && NF {print "  - "$1}' )"
[ -n "$secrets_proj" ]  || secrets_proj="  - (listing unavailable to this credential)"
[ -n "$secrets_stage" ] || secrets_stage="  - (listing unavailable to this credential)"
[ -n "$secrets_prod" ]  || secrets_prod="  - (listing unavailable to this credential)"
integrations="$( { orun integrations list --org "$ws" --json 2>/dev/null || true; } | python3 -c "
import json,sys
try: rows=json.load(sys.stdin)
except Exception: rows=[]
out=[f\"  - {r.get('provider','?')}: {r.get('status','?')}\" for r in rows]
print('\n'.join(out) if out else '  - (listing unavailable to this credential)')" )"

now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Heal the static operator guide from the baseline when the product predates it.
mkdir -p ai/context
if [ ! -f ai/context/operations.md ] && [ -f "$L/ai/context/operations.md" ]; then
  cp "$L/ai/context/operations.md" ai/context/operations.md
  # The baseline copy is written in terms of the baseline's own name; the
  # product copy must speak the product's name. Reuse the rebrand values.
  node "$L/tooling/rebrand/rebrand.mjs" --values "$vals" --allow-dirty >/dev/null 2>&1 || true
  echo "render-docs: healed ai/context/operations.md from baseline"
fi

cat > ai/context/deployment.md <<EOF
# ${repo} — live deployment manifest

> GENERATED by \`flows/phases/08-docs\` on ${now}. Re-run that phase to
> refresh (idempotent). Hand-edits here are overwritten. Operating guide:
> [operations.md](operations.md). No secret values appear in this file —
> inventories are names only.

## Identity

| | |
|---|---|
| product / project slug | \`${repo}\` |
| Orun workspace | \`${ws}\` (slug \`${slug}\`) |
| declared in | \`intent.yaml\` → \`execution.state.workspace\` / \`.project\` |
| baseline provenance | \`${bsrc}\` (see [fork-from-baseline.md](fork-from-baseline.md)) |
| CI lane CLI pin | orun \`${lanepin}\` (\`.github/workflows/ci.yml\`) |

## Public URLs (probed ${now})

| surface | URL | status |
|---|---|---|
| edge API (stage) | ${edge_stage}/health | $(badge "$p_es") |
| edge API (prod) | ${edge_prod}/health | $(badge "$p_ep") |
| console (stage) | ${con_stage} | $(badge "$p_cs") |
| console (prod) | ${con_prod} | $(badge "$p_cp") |
${dom_rows}

A 401/403 on \`/health\` still counts as deployed (alive but unauthorized);
000/5xx does not. The \`dev\` environment is verify-only by design — no
deployed URLs.

## Environments

- \`stage\` and \`prod\` are fully provisioned (Supabase project, Hyperdrive,
  idempotency KV, migrations) and serve the URLs above.
- \`dev\` is verify-only: plan/verify lanes run, nothing is deployed.

## Secrets inventory (names only)

Project rung:
${secrets_proj}

Environment \`stage\`:
${secrets_stage}

Environment \`prod\`:
${secrets_prod}

Provider secrets are BROKERED (minted per-run from the workspace's
integration connections; no long-lived values at rest). \`WIRING_*\` and
\`SUPABASE_*\` env-rung entries are job-output secrets published by the
infrastructure terraform — deploy lanes resolve them for worker bindings.

## Workspace integrations

${integrations}

## How this deployment changes

Merges to \`main\` converge automatically: CI plans changed components and
runs each lane via \`orun run --remote-state\` against the workspace above.
See [operations.md](operations.md) for the full operating contract
(convergence, resumes, secrets, verification, troubleshooting).
EOF
echo "render-docs: wrote ai/context/deployment.md"

# README section between markers (append the section if the README predates it).
python3 - "$repo" <<'PY'
import re, sys
repo = sys.argv[1]
begin, end = "<!-- 08-docs:begin -->", "<!-- 08-docs:end -->"
body = f"""{begin}
This product is **live**. Verified URLs, identity, secrets inventory, and
provenance are recorded in [ai/context/deployment.md](ai/context/deployment.md)
(regenerated by [`flows/phases/08-docs`](flows/phases/08-docs/README.md));
the operating contract lives in
[ai/context/operations.md](ai/context/operations.md).
{end}"""
s = open("README.md").read()
if begin in s and end in s:
    s = re.sub(re.escape(begin) + r".*?" + re.escape(end), body, s, count=1, flags=re.S)
else:
    # READMEs that predate the markers get the section right after the title.
    lines = s.splitlines(keepends=True)
    insert_at = 1
    while insert_at < len(lines) and lines[insert_at].strip() == "":
        insert_at += 1
    section = f"\n## Live deployment\n\n{body}\n"
    lines.insert(insert_at, section)
    s = "".join(lines)
open("README.md", "w").write(s)
print("render-docs: README live-deployment section rendered")
PY

# The contract for verify: no placeholder tokens survive a render.
if grep -rn "TBD_08DOCS" ai/context README.md 2>/dev/null | grep -v Binary; then
  echo "render-docs: placeholder tokens remain (above)" >&2
  exit 1
fi
echo "render-docs: done"
