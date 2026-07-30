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
set -euo pipefail

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
git push -qu origin "$branch"

pr_url="$(gh pr create --title "$title" --body "$body")"
echo "land-pr: PR $pr_url"

if [ "$no_wait" = "true" ]; then
  echo "land-pr: --no-wait — merging now; the convergence run is the gate"
  gh pr merge "$pr_url" --squash --delete-branch 2>/dev/null \
    || gh pr merge "$pr_url" --squash --admin --delete-branch
  git checkout main -q
  git pull -q
  echo "land-pr: merged $pr_url"
  exit 0
fi

# Wait for PR checks; a repo with no checks configured reports none — proceed.
sleep 20
for _ in $(seq 1 90); do
  state="$(gh pr checks "$pr_url" --json bucket \
    --jq 'if length == 0 then "none" elif all(.[].bucket; . != "pending") then "done" else "pending" end' 2>/dev/null || echo none)"
  [ "$state" != "pending" ] && break
  sleep 30
done
if [ "${state:-none}" = "done" ]; then
  fails="$(gh pr checks "$pr_url" --json bucket --jq '[.[]|select(.bucket=="fail")]|length')"
  if [ "$fails" != "0" ]; then
    echo "land-pr: $fails check(s) failed on the PR:" >&2
    gh pr checks "$pr_url" --json name,bucket --jq '.[]|select(.bucket=="fail")|.name' >&2
    exit 1
  fi
fi

gh pr merge "$pr_url" --squash --delete-branch 2>/dev/null \
  || gh pr merge "$pr_url" --squash --admin --delete-branch
git checkout main -q
git pull -q
echo "land-pr: merged $pr_url"
