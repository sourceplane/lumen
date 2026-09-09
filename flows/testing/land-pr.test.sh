#!/usr/bin/env bash
# The BT2 contract test for flows/common/land-pr.sh: a tracked landing goes
# through the pen (branch orun/<KEY>-<suffix>, Orun-Task trailer on the
# commit, `Task: KEY` + manifest in the body, label attempted), merges, and
# leaves the checkout on a main that carries the change; an untracked
# landing is today's phase/<suffix>-<epoch> path; a pen that refuses the PR
# merges the orun/… branch directly with the trailer.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export PATH="$here/fake-orun:$here/fake-gh:$PATH" FAKE_ORUN_STATE="$tmp/state.json" FAKE_GH_LOG="$tmp/gh.log" GH_TOKEN=fake
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
fail() { echo "FAIL: $*" >&2; exit 1; }
fresh_repo() { # → path of a product clone with a bare origin
  local d="$tmp/$1"; rm -rf "$d" "$d.git"
  git init -q --bare "$d.git"; git init -q -b main "$d"
  git -C "$d" remote add origin "$d.git"; echo hi > "$d/README.md"; git -C "$d" add -A; git -C "$d" commit -qm init; git -C "$d" push -qu origin main
  echo "$d"
}

echo "── 1. tracked landing through the pen"
P="$(fresh_repo p1)"; echo change > "$P/infra.tf"
export FAKE_ORUN_PEN_BODY="$tmp/body1"
out="$("$root/flows/common/land-pr.sh" --no-wait --task BASE-3 --epic infra-baselining "$P" 03-infrastructure "phase(03-infrastructure): d1, kv, db-migrate" 2>&1)" || fail "land-pr: $out"
echo "$out" | grep -q "land-pr: PR #7 on orun/BASE-3-03-infrastructure (task BASE-3)" || fail "pen line missing: $out"
echo "$out" | grep -q "land-pr: merged #7" || fail "merge line missing: $out"
git -C "$P.git" branch --list 'orun/*' | grep -q "orun/BASE-3-03-infrastructure" || fail "grammar branch not pushed"
git -C "$P.git" log -1 --format=%B orun/BASE-3-03-infrastructure | grep -q "^Orun-Task: BASE-3$" || fail "commit lacks the trailer"
grep -q "^Task: BASE-3$" "$tmp/body1" && grep -q '"epic":"infra-baselining"' "$tmp/body1" || fail "body lacks trailer/manifest: $(cat "$tmp/body1")"
grep -q "pr edit 7 --add-label orun:task/BASE-3" "$FAKE_GH_LOG" || fail "label not attempted: $(cat "$FAKE_GH_LOG")"
[ "$(git -C "$P" rev-parse --abbrev-ref HEAD)" = main ] && [ -f "$P/infra.tf" ] && git -C "$P" diff --quiet origin/main || fail "checkout not back on a pulled main"
git -C "$P" branch --list 'landing/*' | grep -q . && fail "scratch branch left behind"

echo "── 2. untracked landing is today's path"
P="$(fresh_repo p2)"; echo change > "$P/x"
: > "$FAKE_GH_LOG"
# (No PR token here, so the untracked path takes its own direct-merge
# fallback — which deletes the phase/… branch after merging it.)
out="$(GH_TOKEN= "$root/flows/common/land-pr.sh" --no-wait "$P" 02-foundation "phase(02-foundation): shared packages" 2>/dev/null)" || true
echo "$out" | grep -q "landed phase/02-foundation-" || fail "untracked path not taken: $out"
git -C "$P.git" log -1 --format=%s main | grep -q "phase(02-foundation): shared packages" || fail "untracked landing not on main"
git -C "$P.git" log -3 --format=%B main | grep -q "Orun-Task" && fail "untracked landing carries a trailer"
git -C "$P.git" branch --list 'orun/*' | grep -q . && fail "untracked landing touched the grammar"

echo "── 3. pen refuses the PR: orun/… branch merged directly, trailer kept"
P="$(fresh_repo p3)"; echo change > "$P/y"
out="$(FAKE_ORUN_PEN_REFUSE=1 "$root/flows/common/land-pr.sh" --no-wait --task BASE-4 "$P" 04-workers "phase(04-workers): worker fleet" 2>&1)" || fail "refused pen: $out"
echo "$out" | grep -q "landed orun/BASE-4-04-workers on main directly" || fail "direct landing line missing: $out"
git -C "$P.git" log -1 --format=%B main | grep -q "^Orun-Task: BASE-4$" || fail "merge commit lacks the trailer"

echo "── 4. a suffix outside the grammar lands untracked, loudly"
P="$(fresh_repo p4)"; echo change > "$P/z"
out="$("$root/flows/common/land-pr.sh" --no-wait --task BASE-5 "$P" "04_Workers" "t" 2>&1)" || true
echo "$out" | grep -q "outside the branch grammar" || fail "bad suffix not narrated: $out"
git -C "$P.git" branch --list 'orun/*' | grep -q . && fail "bad suffix reached the grammar"

echo "── 5. push-main with a task takes the pen"
P="$(fresh_repo p5)"; echo docs > "$P/ai.md"
out="$(cd "$P" && "$root/flows/common/push-main.sh" --task BASE-8 --epic infra-baselining 08-docs "docs(deployment): record live deployment state" 2>&1)" || fail "push-main: $out"
git -C "$P.git" branch --list 'orun/*' | grep -q "orun/BASE-8-08-docs" || fail "push-main did not take the pen: $out"
echo "land-pr.test.sh: all claims hold"
