#!/usr/bin/env bash
# Force components into the next convergence's changed set.
#
#   flows/common/redeploy-marker.sh <product-dir> <reason> <component-dir>…
#
# WHY THIS EXISTS — the trap it defuses:
#
# The product's CI plans with `orun plan --changed` (.github/workflows/ci.yml):
# a component deploys only when files under its directory changed in the push.
# That makes convergence cheap, and it is correct as long as
# "content unchanged" implies "already deployed".
#
# A FAILED convergence breaks that implication. The content is on main; the
# deploy never happened. Re-running the phase then re-applies the SAME content,
# `--changed` sees no diff, the plan is empty, and the component is never
# deployed — no matter how many times the phase is retried. The bootstrap makes
# progress on paper and none in the account. (Hit live on nexara: three full
# umbrella attempts, and metering/admin/config/events/policy/projects-worker
# were never deployed once. Phase 05 only discovered it when api-edge's own
# deploy failed with "Service binding 'METERING_WORKER' references Worker
# 'nexara-metering-worker-prod' which was not found".)
#
# Stamping a `# ci: <reason>` line onto component.yaml puts the component back
# in the changed set with no behavioural diff. Every deploy is an upsert, so
# re-deploying an already-live component is a no-op that costs only CI time —
# which is why the retry path can stamp broadly rather than trying to work out
# exactly which components are missing (it cannot: internal workers set
# workers_dev:false and are not observable from outside the account).
#
# The marker is a comment at the END of the file, so it never collides with
# YAML structure and successive markers accumulate as a legible history of why
# each forced deploy happened.
set -euo pipefail

out="${1:?redeploy-marker: product repo dir}"
reason="${2:?redeploy-marker: reason}"
shift 2
[ "$#" -gt 0 ] || { echo "redeploy-marker: name at least one component dir" >&2; exit 1; }

# One timestamp for the whole batch: components stamped together read as one
# recovery action rather than a scatter of unrelated ones.
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
marked=0
missing=0

for dir in "$@"; do
  f="$out/$dir/component.yaml"
  if [ ! -f "$f" ]; then
    # Not an error: phases stamp their own component set, and a component may
    # legitimately not exist yet (the console before phase 06, say).
    missing=$((missing + 1))
    continue
  fi
  # Trailing newline first — appending to a file whose last line has none
  # would splice the marker onto it and corrupt the YAML.
  [ -z "$(tail -c 1 "$f")" ] || printf '\n' >> "$f"
  printf '# ci: %s (%s)\n' "$reason" "$stamp" >> "$f"
  marked=$((marked + 1))
done

note=""
[ "$missing" -eq 0 ] || note=" ($missing not present yet)"
echo "redeploy-marker: stamped $marked component(s) for '$reason'$note"
[ "$marked" -gt 0 ] || echo "redeploy-marker: nothing stamped — the convergence will be a no-op if the content is unchanged" >&2
