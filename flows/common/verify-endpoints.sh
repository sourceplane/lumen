#!/usr/bin/env bash
# Probe the product's deployed endpoints, derived from .rebrand/values.json.
# Pass the surfaces to check: "edge" (api-edge /health) and/or "console".
#
#   flows/common/verify-endpoints.sh <out> <edge|console> [edge|console…]
#
# STRICTNESS — why /health must be exactly 200:
#
# This check used to accept anything in 200–499 as healthy. That made it blind
# to the one failure it exists to catch: an UNDEPLOYED worker. A workers.dev
# hostname with no live script behind it answers 404 — so a product that never
# deployed passed verification with a row of ✓. (Hit live on nexara: api-edge
# was absent from prod for the entire bootstrap and verification stayed green.)
#
# A deployed api-edge answers /health with 200 by contract, so 200 is the only
# honest bar. The console is a page rather than a health contract, so it takes
# any non-error response (2xx/3xx) — but 4xx and 5xx now fail there too.
set -euo pipefail

out="${1:?product repo dir}"
shift
[ "$#" -gt 0 ] || { echo "verify-endpoints: name at least one surface (edge|console)" >&2; exit 1; }

vals="$out/.rebrand/values.json"
repo="$(python3 -c "import json;print(json.load(open('$vals'))['repoName'])")"
sub="$(python3 -c "import json;print(json.load(open('$vals'))['workersDevSubdomain'])")"

# "url<TAB>kind" — kind selects the acceptance rule below.
probes=()
for surface in "$@"; do
  case "$surface" in
    edge)
      probes+=("https://${repo}-api-edge-stage.${sub}.workers.dev/health	health")
      probes+=("https://${repo}-api-edge-prod.${sub}.workers.dev/health	health")
      ;;
    console)
      probes+=("https://${repo}-web-console-next-stage.${sub}.workers.dev	page")
      probes+=("https://${repo}-web-console-next-prod.${sub}.workers.dev	page")
      ;;
    *) echo "verify-endpoints: unknown surface $surface" >&2; exit 2 ;;
  esac
done

ok=0; fail=0
for probe in "${probes[@]}"; do
  url="${probe%%	*}"; kind="${probe##*	}"
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "$url" || echo 000)"
  accepted=false
  case "$kind" in
    health) [ "$code" = "200" ] && accepted=true ;;
    page)   { [ "$code" -ge 200 ] && [ "$code" -lt 400 ]; } 2>/dev/null && accepted=true ;;
  esac
  if [ "$accepted" = "true" ]; then
    echo "✓ $url → $code"; ok=$((ok+1))
  else
    echo "✕ $url → $code" >&2
    # 404 on workers.dev is the signature of "no script behind this hostname" —
    # a deploy that never happened. Say so: it reads like a routing bug and
    # sends people looking in the wrong place.
    [ "$code" = "404" ] && echo "  ↳ 404 on workers.dev = nothing deployed at this name (not a routing fault) — check that component's deploy lane in the last main convergence" >&2
    fail=$((fail+1))
  fi
done
[ "$fail" -eq 0 ] || { echo "$fail endpoint(s) unhealthy" >&2; exit 1; }
echo "verify-endpoints: $ok healthy"
