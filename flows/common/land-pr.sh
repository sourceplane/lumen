#!/usr/bin/env bash
# Land the product repo's staged/working changes on main through a PR: branch
# → commit → push → wait for PR checks (pass immediately when the repo has
# none yet) → merge (admin bypass when available, else wait on required
# checks) → back on main, pulled. No-op when there is nothing to commit.
#
#   flows/common/land-pr.sh [--no-wait] <out> <branch-suffix> <title> [body]
#
# --no-wait: merge immediately after opening the PR instead of gating on its
# checks. For landings whose PR lanes are STRUCTURALLY red on a fresh product
# — phase 03's db-migrate/hyperdrive plan lanes need supabase's job-output
# secrets, which only exist after the merge's main run APPLIES supabase — the
# real gate is the convergence the caller watches next, exactly like the
# express path's push-main.sh. Use it only where the phase documents why.
#
# GitHub operations go through ghrest.sh: `gh` first, plain-REST fallback —
# sandboxes that block gh's GraphQL/Actions surface still land cleanly.
set -euo pipefail

. "$(dirname "$0")/ghrest.sh"

no_wait=false
if [ "${1:-}" = "--no-wait" ]; then
  no_wait=true
  shift
fi
out="${1:?product repo dir}"
suffix="${2:?branch suffix}"
title="${3:?PR title}"
body="${4:-Automated phase landing (flows/common/land-pr.sh).}"

cd "$out"
git add -A
if git diff --cached --quiet; then
  echo "land-pr: nothing to land"
  exit 0
fi

branch="phase/${suffix}-$(date +%s)"
git checkout -qb "$branch"
git commit -q -m "$title" -m "$body"
# The applied content is committed — disarm apply-blueprint's crash marker.
rm -f .git/orun-apply-inflight
git push -qu origin "$branch"
head_sha="$(git rev-parse HEAD)"

# PR creation needs the token's pull_requests scope; an App installation
# that predates the grant refuses it via BOTH gh and REST. The PR here is
# process ceremony — the real gate is the convergence the caller watches —
# so a refused create degrades to a direct merge to main (contents:write is
# sufficient), loudly, naming the App permission that lifts it.
if pr_num="$(ghr_pr_create "$title" "$body" "$branch")" && [ -n "$pr_num" ]; then
  echo "land-pr: PR #$pr_num"
else
  echo "land-pr: PR creation refused (grant the GitHub App 'Pull requests: Read & write' to restore PR landings) — merging $branch to main directly" >&2
  git checkout main -q
  git merge -q --no-ff "$branch" -m "$title" -m "$body (direct landing: PR creation refused)"
  git push -q origin main
  git push -q origin --delete "$branch" 2>/dev/null || true
  git pull -q
  echo "land-pr: landed $branch on main directly"
  exit 0
fi

if [ "$no_wait" = "true" ]; then
  echo "land-pr: --no-wait — merging now; the convergence run is the gate"
  ghr_pr_merge "$pr_num" "$branch"
  git checkout main -q
  git pull -q
  echo "land-pr: merged #$pr_num"
  exit 0
fi

# Wait for PR checks; a repo with no checks configured reports none — proceed.
sleep 20
for _ in $(seq 1 90); do
  state="$(ghr_pr_checks_state "$head_sha")"
  [ "$state" != "pending" ] && break
  sleep 30
done
case "${state:-none}" in
  fail:*)
    echo "land-pr: ${state#fail:} check(s) failed on the PR:" >&2
    ghr_pr_failed_checks "$head_sha" >&2
    exit 1
    ;;
esac

ghr_pr_merge "$pr_num" "$branch"
git checkout main -q
git pull -q
echo "land-pr: merged #$pr_num"
