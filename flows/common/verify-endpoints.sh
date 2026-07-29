#!/usr/bin/env bash
# Probe the product's deployed endpoints, derived from .rebrand/values.json.
# Pass the surfaces to check: "edge" (api-edge /health) and/or "console".
#
#   flows/common/verify-endpoints.sh <out> <edge|console> [edge|console…]
set -euo pipefail

out="${1:?product repo dir}"
shift
[ "$#" -gt 0 ] || { echo "verify-endpoints: name at least one surface (edge|console)" >&2; exit 1; }

vals="$out/.rebrand/values.json"
repo="$(python3 -c "import json;print(json.load(open('$vals'))['repoName'])")"
sub="$(python3 -c "import json;print(json.load(open('$vals'))['workersDevSubdomain'])")"

urls=()
for surface in "$@"; do
  case "$surface" in
    edge)
      urls+=("https://${repo}-api-edge-stage.${sub}.workers.dev/health")
      urls+=("https://${repo}-api-edge-prod.${sub}.workers.dev/health")
      ;;
    console)
      urls+=("https://${repo}-web-console-next-stage.${sub}.workers.dev")
      urls+=("https://${repo}-web-console-next-prod.${sub}.workers.dev")
      ;;
    *) echo "verify-endpoints: unknown surface $surface" >&2; exit 2 ;;
  esac
done

ok=0; fail=0
for url in "${urls[@]}"; do
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "$url" || echo 000)"
  if [ "$code" -ge 200 ] && [ "$code" -lt 500 ]; then
    echo "✓ $url → $code"; ok=$((ok+1))
  else
    echo "✕ $url → $code" >&2; fail=$((fail+1))
  fi
done
[ "$fail" -eq 0 ] || { echo "$fail endpoint(s) unhealthy" >&2; exit 1; }
echo "verify-endpoints: $ok healthy"
