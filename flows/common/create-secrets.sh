#!/usr/bin/env bash
# Create this product's five provider secrets from the workspace's
# integrations — brokered/fact templates only, so NO credential value is ever
# typed, seen, or stored here. Idempotent: keys that already exist are kept.
# The argument is the workspace id (ws_…) or slug; the CLI flag it feeds is
# named --org for historical reasons.
#
#   flows/common/create-secrets.sh <workspace-id-or-slug> [--dry-run|true]
#
# Dry run (second arg "--dry-run" or "true"): report per-key what WOULD
# happen (kept / recreated / created) against the current connections and
# exit without creating, revoking, or rotating anything.
#
# | Key                         | Provider   | Template          | What resolves |
# |-----------------------------|------------|-------------------|---------------|
# | CLOUDFLARE_API_TOKEN        | cloudflare | workers-deploy    | fresh per-run worker-deploy token |
# | CLOUDFLARE_HYPERDRIVE_TOKEN | cloudflare | hyperdrive-edit   | fresh per-run Hyperdrive token    |
# | CLOUDFLARE_ACCOUNT_ID       | cloudflare | account-id        | connection fact (non-secret)      |
# | SUPABASE_ACCESS_TOKEN       | supabase   | management-access | fresh per-run management token    |
# | SUPABASE_ORG_ID             | supabase   | org-id            | connection fact (non-secret)      |
set -euo pipefail

org="${1:?usage: create-secrets.sh <workspace-id-or-slug> [--dry-run|true]}"
dry_run=0
case "${2:-}" in --dry-run|true) dry_run=1 ;; esac

connections="$(orun integrations list --org "$org" --json)"
conn_for() {
  # First ACTIVE connection id for the provider.
  printf '%s' "$connections" | python3 -c "
import json,sys
rows=json.load(sys.stdin)
for r in rows:
    if r.get('provider')=='$1' and r.get('status')=='active':
        print(r['id']); break
"
}

cf="$(conn_for cloudflare)"
sb="$(conn_for supabase)"
[ -n "$cf" ] || { echo "no active cloudflare connection in $org" >&2; exit 1; }
[ -n "$sb" ] || { echo "no active supabase connection in $org" >&2; exit 1; }

existing="$(orun secrets list --org "$org" --project --json 2>/dev/null || echo '[]')"

# healthy KEY → 0 when the key exists AND is not orphaned (its broker
# connection can still mint). An orphaned key (bound to a revoked/replaced
# connection) is revoked and recreated against the CURRENT connection.
state() {
  printf '%s' "$existing" | python3 -c "
import json,sys
rows=json.load(sys.stdin)
for r in rows:
    if r.get('secretKey')=='$1' or r.get('key')=='$1':
        print('orphaned' if (r.get('health')=='orphaned' or r.get('orphaned')) else 'ok'); break
else:
    print('absent')
"
}

create() { # key provider connection template
  case "$(state "$1")" in
    ok)      echo "✓ $1 exists and is healthy — kept"; return ;;
    orphaned)
      if [ "$dry_run" = "1" ]; then
        echo "DRY RUN: ↻ $1 is orphaned — would revoke and recreate against $3 ($2/$4)"
        return
      fi
      echo "↻ $1 is orphaned (its connection was revoked) — recreating against the current connection"
      orun secrets revoke "$1" --org "$org" --project --yes 2>/dev/null || orun secrets revoke "$1" --org "$org" --project 2>/dev/null || true
      ;;
    absent)
      if [ "$dry_run" = "1" ]; then
        echo "DRY RUN: + $1 would be created against $3 ($2/$4)"
        return
      fi
      ;;
  esac
  if ! orun integrations "$2" secret create "$1" --org "$org" --connection "$3" --template "$4" --project; then
    # Resource-hiding masks authorization as not_found: when READS work
    # (this script already listed connections and secrets) but the WRITE
    # 404s, the credential is almost always a read-only (viewer-role) API
    # key. Say so — the raw error sends people chasing missing scopes.
    echo "create-secrets: writing $1 failed. If the listings above worked, this ORUN_TOKEN's role is below ADMIN — brokered secret creation requires an admin-role API key (builder and viewer keys read fine but writes come back not_found; resource-hiding masks the denial). Re-mint the workspace API key with the ADMIN role in the console and re-run — this script is idempotent." >&2
    exit 1
  fi
  echo "✓ $1 created ($2/$4)"
}

create CLOUDFLARE_API_TOKEN        cloudflare "$cf" workers-deploy
create CLOUDFLARE_HYPERDRIVE_TOKEN cloudflare "$cf" hyperdrive-edit
create CLOUDFLARE_ACCOUNT_ID       cloudflare "$cf" account-id
create SUPABASE_ACCESS_TOKEN       supabase   "$sb" management-access
create SUPABASE_ORG_ID             supabase   "$sb" org-id

if [ "$dry_run" = "1" ]; then
  echo "DRY RUN: no secrets were created, revoked, or rotated."
  exit 0
fi
echo "secrets ready:"
orun secrets list --org "$org" --project
