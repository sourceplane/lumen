#!/usr/bin/env bash
# Workspace readiness gate, shared by every deploy phase and the express flow.
# Idempotent and fast when healthy: auth → one authoritative integrations
# probe → poll for ACTIVE github+cloudflare+supabase (up to 10m, so consents
# can be clicked while it waits) → repo allow-list, self-healing via
# `orun cloud link`. Run it FROM the product repo (the link needs its remote).
#
#   flows/common/preflight.sh <workspace-id-or-slug>
set -euo pipefail

ws="${1:?usage: preflight.sh <workspace-id-or-slug>}"

echo "── auth"
# Headless mode (ORUN_TOKEN set): the CLI authenticates from the env var and
# there is no stored session for auth status to show — the integrations
# probe below is the real auth check. Interactive mode still requires a
# login so the failure message stays actionable.
if [ -n "${ORUN_TOKEN:-}" ]; then
  echo "auth: ORUN_TOKEN (headless)"
else
  orun auth status | grep -q "User:" || {
    echo "not logged in: run \`orun auth login --device\` and approve at https://app.orun.dev/cli/device (or set ORUN_TOKEN for headless runs)" >&2
    exit 1
  }
fi

echo "── integrations (ACTIVE github+cloudflare+supabase; polling up to 10m so consents can be clicked now)"
# One authoritative probe FIRST: if the command itself fails (stale CLI,
# revoked session, bad workspace id), fail loudly with its stderr — never
# misread a broken command as "not connected yet" and poll forever.
if ! probe="$(orun integrations list --org "$ws" --json 2>&1)"; then
  echo "orun integrations list failed — fix this before anything can poll:" >&2
  echo "$probe" >&2
  echo "(common causes: an old orun earlier in PATH — check \`which -a orun\`, need >= v2.49.2; or the CLI session expired — \`orun auth login\`)" >&2
  exit 1
fi
active() {
  orun integrations list --org "$ws" --json 2>/dev/null | python3 -c "
import json,sys
try:
    rows=json.load(sys.stdin)
except Exception:
    sys.exit(1)
sys.exit(0 if any(r.get('provider')=='$1' and r.get('status')=='active' for r in rows) else 1)"
}
deadline=$(( $(date +%s) + 600 ))
while :; do
  missing=""
  active github     || missing="github"
  active cloudflare || missing="${missing:+$missing }cloudflare"
  active supabase   || missing="${missing:+$missing }supabase"
  [ -z "$missing" ] && break
  if [ "$(date +%s)" -ge "$deadline" ]; then
    echo "still missing ACTIVE connection(s) after 10m: $missing — connect them in the console (Integrations)." >&2
    exit 1
  fi
  echo "waiting for connection(s): $missing → console → Integrations ($ws)"
  sleep 20
done

echo "── repo link + allow-list (idempotent)"
# Link FIRST, unconditionally: `orun cloud check` consults the server-side
# allow-list and can pass while the LOCAL link cache (HOME config) is empty —
# a fresh container HOME — leaving later project-scoped commands to die with
# "this repo isn't connected" (hit live). Linking is an idempotent no-op when
# already linked and also populates the cache.
orun cloud link --org "$ws" >/dev/null 2>&1 || true
orun cloud check --org "$ws" || {
  echo "repo not allow-listed for $ws: grant it in the console (Git Repos)" >&2
  exit 1
}
echo "preflight ok"
