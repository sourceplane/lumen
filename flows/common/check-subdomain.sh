#!/usr/bin/env bash
# Validate the workers.dev subdomain input BEFORE it is baked into a product.
#
#   flows/common/check-subdomain.sh <subdomain>
#
# WHY — the failure this catches:
#
# `subdomain` is the Cloudflare ACCOUNT's workers.dev subdomain. It is easy to
# read the input as "a subdomain for my product" and pass the product name,
# which is always wrong and never noticed: the deploy succeeds (worker names
# are unaffected), and every URL the product then advertises — its own docs,
# the api-edge CORS allowlist, the OAuth redirect base, the verification
# probes — points at a hostname that does not exist. The product is live and
# unreachable at every address it knows about. (Hit live on nexara: bootstrapped
# with subdomain=nexara against an account whose real subdomain is different;
# the console would have been CORS-rejected by its own API.)
#
# THE PROBE — no credentials needed:
#
# workers.dev publishes DNS only for CLAIMED subdomains. An unclaimed one is
# NXDOMAIN; a claimed one resolves and answers 404 for a worker that does not
# exist. So a single lookup separates the two:
#
#   <anything>.rahulvarghesepullely.workers.dev → 172.67.x.x  (claimed)
#   <anything>.nexara.workers.dev               → NXDOMAIN    (not claimed)
#
# This says the subdomain EXISTS, not that it is yours — a typo landing on
# someone else's subdomain still passes. It is a cheap guard against the
# common mistake, not an authorization check.
set -euo pipefail

sub="${1:?check-subdomain: subdomain required}"
probe="orun-bootstrap-probe.${sub}.workers.dev"

# Prefer a DNS lookup (fast, unambiguous); fall back to curl where dig is
# absent — a connection failure there is the same NXDOMAIN signal.
resolved=""
if command -v dig >/dev/null 2>&1; then
  resolved="$(dig +short +time=3 +tries=2 "$probe" 2>/dev/null | head -1)"
elif command -v getent >/dev/null 2>&1; then
  resolved="$(getent hosts "$probe" 2>/dev/null | head -1)"
else
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "https://$probe" 2>/dev/null || echo 000)"
  [ "$code" = "000" ] || resolved="http:$code"
fi

if [ -n "$resolved" ]; then
  echo "✓ workers.dev subdomain '$sub' is claimed and resolving"
  exit 0
fi

cat >&2 <<EOF
✕ workers.dev subdomain '$sub' does not resolve — nothing is published at
  *.${sub}.workers.dev, so this is not a claimed Cloudflare subdomain.

  This input is the Cloudflare ACCOUNT's workers.dev subdomain, NOT a name for
  the product. Passing the product name here is the usual mistake: everything
  deploys fine and every URL the product advertises is dead — its docs, the
  api-edge CORS allowlist, the OAuth redirect base, and every verification
  probe.

  Find the real value in the Cloudflare dashboard under Workers & Pages; it is
  shown as "*.<subdomain>.workers.dev" on the account's Workers overview.

  Re-run with --set subdomain=<that value>.
EOF
exit 1
