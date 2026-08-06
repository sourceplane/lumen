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
if [ -n "${ORUN_TOKEN:-}${ORUN_TOKEN_FILE:-}" ]; then
  echo "auth: headless (ORUN_TOKEN${ORUN_TOKEN_FILE:+/ORUN_TOKEN_FILE})"
else
  # Capture, THEN match — never `orun auth status | grep -q`. `grep -q` exits
  # on the first match, `orun` takes SIGPIPE writing the rest of the org list,
  # and `set -o pipefail` turns that 141 into a pipeline failure: a perfectly
  # logged-in CLI is reported as "not logged in". Only interactive runs reach
  # this branch, which is why it survived so long (headless sets ORUN_TOKEN and
  # short-circuits above). Hit live on a local-mode bootstrap.
  auth_out="$(orun auth status 2>&1 || true)"
  case "$auth_out" in
    *"User:"*) ;;
    *)
      echo "not logged in: run \`orun auth login --device\` and approve at https://app.orun.dev/cli/device (or set ORUN_TOKEN for headless runs)" >&2
      [ -n "$auth_out" ] && printf '%s\n' "$auth_out" >&2
      exit 1
      ;;
  esac
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
# already linked and also populates the cache. It legitimately FAILS for
# workspace-scoped tokens (they may not write links) — tolerated but said
# out loud, because project resolution then rests on the intent declaring
# the project (healed below).
orun cloud link --org "$ws" >/dev/null 2>&1 \
  || echo "note: cloud link not written (workspace-scoped token?) — relying on intent.yaml project declaration"
orun cloud check --org "$ws" || {
  echo "repo not allow-listed for workspace $ws." >&2
  echo "This is the ONE step a workspace-scoped token cannot do itself:" >&2
  echo "  console → workspace $ws → Settings → Git repos → add this repo" >&2
  echo "Then re-run this phase (idempotent). Do this ONCE per product, ideally before phase 01." >&2
  exit 1
}

# Self-heal: products scaffolded before the project declaration existed lack
# `project:` in execution.state, and without a local repo link every
# project-scoped command (secrets --project/--env) dies headless. Insert
# `project: <repoName>` beside `workspace:` and push it to main — a durable
# heal, like the scaffold pushes (no-op when already declared).
if [ -f intent.yaml ] && ! grep -qE '^\s*project:' intent.yaml; then
  proj="$(python3 -c "import json;print((json.load(open('.rebrand/values.json')).get('repoName') or '').strip())" 2>/dev/null || true)"
  if [ -n "$proj" ]; then
    python3 - "$proj" <<'PY'
import re, sys
proj = sys.argv[1]
s = open("intent.yaml").read()
s2 = re.sub(r"^(\s*)(workspace:.*)$", r"\g<1>\g<2>\n\g<1>project: " + proj, s, count=1, flags=re.M)
open("intent.yaml", "w").write(s2)
PY
    if ! git diff --quiet -- intent.yaml; then
      echo "healing intent.yaml: declaring project: $proj"
      "$(dirname "$0")/push-main.sh" intent-project \
        "chore(intent): declare project beside workspace" \
        "Headless runs authenticate with workspace-scoped tokens, which cannot write the repo link that project resolution falls back to; the intent must declare the project." \
        || { echo "push of intent project heal failed" >&2; exit 1; }
    fi
  fi
fi
echo "preflight ok"
