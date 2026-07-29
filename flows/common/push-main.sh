#!/usr/bin/env bash
# Land the current working-tree changes on main, honoring repos where main is
# PR-only (repository rules): branch → PR → immediate admin merge. The merge
# commit's main run is the convergence the caller waits on. Falls back to
# plain merge when the actor lacks admin bypass; in that case required checks
# must pass first (bootstrap PRs' own lanes are plan/verify-only).
#
#   flows/common/push-main.sh <branch-suffix> <title> [body]
set -euo pipefail

suffix="${1:?usage: push-main.sh <branch-suffix> <title> [body]}"
title="${2:?usage: push-main.sh <branch-suffix> <title> [body]}"
body="${3:-Automated bootstrap push (flows/common/push-main.sh).}"

if git diff --quiet && git diff --cached --quiet; then
  echo "push-main: nothing to land"
  exit 0
fi

branch="bootstrap/${suffix}-$(date +%s)"
git checkout -qb "${branch}"
git add -A
git commit -q -m "${title}" -m "${body}"

# Direct push first: repos without a PR-only rule take the fast path.
if git push -q origin "HEAD:main" 2>/dev/null; then
  git checkout main -q && git pull -q
  git branch -qD "${branch}" || true
  echo "push-main: pushed directly to main"
  exit 0
fi

git push -qu origin "${branch}"
pr_url="$(gh pr create --title "${title}" --body "${body}")"
echo "push-main: PR ${pr_url}"
if ! gh pr merge "${pr_url}" --squash --admin --delete-branch 2>/dev/null; then
  echo "push-main: no admin bypass — waiting for required checks"
  until state="$(gh pr checks "${pr_url}" --json bucket \
      --jq 'if length == 0 then "pending" elif all(.[].bucket; . != "pending") then "done" else "pending" end' 2>/dev/null)" \
      && [ "${state}" = "done" ]; do
    sleep 30
  done
  gh pr merge "${pr_url}" --squash --delete-branch
fi
git checkout main -q && git pull -q
echo "push-main: merged ${pr_url}"
