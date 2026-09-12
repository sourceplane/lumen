#!/usr/bin/env bash
# Land the product repo's staged/working changes on main through a PR: branch
# → commit → push → wait for PR checks (pass immediately when the repo has
# none yet) → merge (admin bypass when available, else wait on required
# checks) → back on main, pulled. No-op when there is nothing to commit.
#
#   flows/common/land-pr.sh [--no-wait] [--task KEY] [--epic SLUG] <out> <branch-suffix> <title> [body]
#
# --no-wait: merge immediately after opening the PR instead of gating on its
# checks. For landings whose PR lanes are STRUCTURALLY red on a fresh product
# — phase 03's db-migrate/hyperdrive plan lanes need supabase's job-output
# secrets, which only exist after the merge's main run APPLIES supabase — the
# real gate is the convergence the caller watches next, exactly like the
# express path's push-main.sh. Use it only where the phase documents why.
#
# --task KEY (or ORUN_TASK_KEY): the landing is TRACKED (saas-baseline-tracking
# BT2). The commit carries the Orun-Task trailer, and the branch, push and
# PR go through the pen — `orun pr open --task KEY --branch-slug <suffix>`
# — so the branch is orun/<KEY>-<suffix>, the body carries `Task: KEY` and
# the provenance manifest (with --epic SLUG / ORUN_EPIC_SLUG), and every
# push, PR and merge binds to the task on the platform. The merge and the
# checks wait stay here. Without a key: today's phase/<suffix>-<epoch>
# path, byte-identical — and a pen that is missing or refuses degrades to
# it with one line, never a failed landing.
#
# GitHub operations go through ghrest.sh: `gh` first, plain-REST fallback —
# sandboxes that block gh's GraphQL/Actions surface still land cleanly.
set -euo pipefail

. "$(dirname "$0")/ghrest.sh"

no_wait=false
task="${ORUN_TASK_KEY:-}"
epic="${ORUN_EPIC_SLUG:-}"
while [ $# -gt 0 ]; do
  case "$1" in
    --no-wait) no_wait=true; shift ;;
    --task) task="${2:?--task KEY}"; shift 2 ;;
    --epic) epic="${2:?--epic SLUG}"; shift 2 ;;
    *) break ;;
  esac
done
out="${1:?product repo dir}"
suffix="${2:?branch suffix}"
title="${3:?PR title}"
body="${4:-Automated phase landing (flows/common/land-pr.sh).}"

# Say what is wrong with the ARGUMENT rather than letting `cd` print the whole
# bad value as a directory name. A caller that shadowed this path with command
# output sent a multi-line git transcript here, and the resulting
# `cd: $'To https://…\n * [new branch] main -> main\n…': No such file or
# directory` read as a filesystem fault in this script instead of a bad
# argument from the caller — which cost a live build two identical retries.
if [ ! -d "$out" ]; then
  printf 'land-pr: first argument must be the product repo directory; got %s\n' \
    "$(printf '%s' "$out" | head -1 | cut -c1-80)" >&2
  case "$out" in
    *"$(printf '\n')"*) echo "land-pr: (the value spans multiple lines — the caller passed command output, not a path)" >&2 ;;
  esac
  exit 2
fi

cd "$out"
git add -A
if git diff --cached --quiet; then
  echo "land-pr: nothing to land"
  exit 0
fi

# ── the tracked path's preconditions (each falls back, loudly, to untracked)
tracked=false
if [ -n "$task" ]; then
  if ! printf '%s' "$suffix" | grep -Eq '^[a-z0-9-]+$'; then
    echo "land-pr: suffix '$suffix' is outside the branch grammar's alphabet [a-z0-9-] — landing untracked" >&2
  elif ! command -v orun >/dev/null 2>&1 || ! orun pr open --help 2>/dev/null | grep -q -- '--branch-slug'; then
    echo "land-pr: this orun lacks \`pr open --branch-slug\` — landing untracked (upgrade orun)" >&2
  else
    tracked=true
  fi
fi

if [ "$tracked" = true ]; then
  # Commit on a scratch branch so local main never advances past origin
  # (the pen checks its grammar branch out FROM HEAD).
  scratch="landing/${suffix}-$(date +%s)"
  git checkout -qb "$scratch"
  git commit -q -m "$title" -m "$body" -m "Orun-Task: $task"
  rm -f .git/orun-apply-inflight
  pen_args=(pr open --task "$task" --branch-slug "$suffix" --title "$title" --body-file - --json)
  [ -z "$epic" ] || pen_args+=(--epic "$epic")
  prose="$body"$'\n\n'"Task: $task"
  if pen="$(printf '%s\n' "$prose" | orun "${pen_args[@]}" 2>/dev/null)"; then
    branch="$(printf '%s' "$pen" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("branch",""))')"
    pr_num="$(printf '%s' "$pen" | python3 -c 'import json,sys;d=json.load(sys.stdin);print(d.get("number") or "")')"
    opened="$(printf '%s' "$pen" | python3 -c 'import json,sys;print("yes" if json.load(sys.stdin).get("opened") else "no")')"
  else
    branch="" pr_num="" opened="no"
  fi
  if [ -z "$branch" ]; then
    # The pen never got to the branch: land as before, on the scratch commit.
    echo "land-pr: pen refused before pushing — landing untracked" >&2
    branch="phase/${suffix}-$(date +%s)"
    git branch -m "$branch"
    git push -qu origin "$branch"
    tracked=false
  else
    git branch -qD "$scratch" 2>/dev/null || true
    if [ "$opened" = yes ] && [ -n "$pr_num" ]; then
      echo "land-pr: PR #$pr_num on $branch (task $task)"
      # The label channel, best-effort: the branch already binds.
      ghr_pr_label "$pr_num" "orun:task/$task" || true
    else
      # Pushed, PR refused (no pull_requests grant): the orun/… branch is
      # up, so branch_seen still binds; merge directly as the untracked
      # path does, with the trailer in the merge commit.
      echo "land-pr: PR creation refused (grant the GitHub App 'Pull requests: Read & write' to restore PR landings) — merging $branch to main directly" >&2
      git checkout main -q
      git merge -q --no-ff "$branch" -m "$title" -m "$body (direct landing: PR creation refused)" -m "Orun-Task: $task"
      git push -q origin main
      git push -q origin --delete "$branch" 2>/dev/null || true
      git pull -q
      echo "land-pr: landed $branch on main directly"
      exit 0
    fi
  fi
fi

if [ "$tracked" = false ]; then
  if [ -z "${branch:-}" ]; then
    branch="phase/${suffix}-$(date +%s)"
    git checkout -qb "$branch"
    git commit -q -m "$title" -m "$body"
    # The applied content is committed — disarm apply-blueprint's crash marker.
    rm -f .git/orun-apply-inflight
    git push -qu origin "$branch"
  fi
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
fi
head_sha="$(git rev-parse HEAD)"

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
