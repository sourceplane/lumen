#!/usr/bin/env bash
# A STOPPED BUILD MUST NOT POISON EVERY RETRY.
#
# `orun.pr/land@v1` pushes a phase to the provenance pen's branch,
# `orun/<TASK-KEY>-<phase>`, with a plain `git push -u`. A build that stops
# between that push and the merge leaves the branch and its pull request on the
# remote. The retry re-places the phase and commits a SIBLING of that commit,
# so the push is rejected non-fast-forward — identically, on every retry, for
# ever. Seen on pullely/multi-tenant-saas (2026-10-25): the build stopped after
# 04-workers' PR went green, and every retry after it died on this push without
# reaching one step of the phase's work.
#
# Each landing's `pen-reset` hook (tooling/bootstrap/pen-reset.mjs) clears its
# own branch first. This test asserts the whole chain against a real remote:
# the rejection happens, the tool spots it, the delete unblocks the push, a
# merged branch is left alone, and nothing outside `orun/` can ever be touched.
set -uo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tool="$root/tooling/bootstrap/pen-reset.mjs"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
failures=0
fail() { echo "  ✕ $*" >&2; failures=$((failures + 1)); }
ok() { echo "  ✓ $*"; }

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
git init -q --bare "$tmp/remote"
git init -q "$tmp/work" && cd "$tmp/work"
git config user.email t@example.invalid && git config user.name "pen test"
echo base > f && git add -A && git commit -qm base && git branch -M main
git remote add origin "$tmp/remote" && git push -q -u origin main 2>/dev/null

BR=orun/BASE-5-04-workers

echo "── the guard: only the pen's own namespace"
for bad in main refs/heads/main "orun/../../main" "orun/*" ""; do
  if node "$tool" --branch "$bad" >/dev/null 2>&1; then
    fail "accepted branch '$bad' — the guard must refuse anything but orun/<task>-<slug>"
  fi
done
ok "main, a path escape, a wildcard and an empty name are all refused"

echo "── nothing to clear"
out="$(node "$tool" --branch "$BR" 2>&1)"
[ $? -eq 0 ] && [[ "$out" == *"nothing to clear"* ]] \
  || fail "a branch that is not on the remote should be a quiet no-op, got: $out"
ok "a branch the remote does not have is a no-op"

echo "── a stopped build leaves a branch, and the retry's push is rejected"
git checkout -q -b "$BR" && echo run1 > g && git add -A && git commit -qm "run 1"
git push -q origin "$BR" 2>/dev/null
git checkout -q main
git checkout -q -b retry && echo run2 > g && git add -A && git commit -qm "run 2"
if git push -q origin "retry:$BR" 2>"$tmp/push.err"; then
  fail "the push succeeded — this test no longer reproduces the failure it guards"
else
  grep -q "non-fast-forward" "$tmp/push.err" \
    && ok "the push is rejected non-fast-forward, as it was on the real build" \
    || fail "rejected for another reason: $(head -1 "$tmp/push.err")"
fi

echo "── --check reports it without changing anything"
node "$tool" --branch "$BR" --check >/dev/null 2>&1
[ $? -eq 1 ] || fail "--check should exit non-zero on a diverged branch"
[ "$(git ls-remote --heads origin "$BR" | wc -l)" -eq 1 ] \
  || fail "--check deleted the branch; it must only report"
ok "--check reports the divergence and leaves the branch alone"

echo "── the reset clears it and the same push then succeeds"
node "$tool" --branch "$BR" >/dev/null 2>&1 || fail "the reset failed"
[ "$(git ls-remote --heads origin "$BR" | wc -l)" -eq 0 ] || fail "the branch is still on the remote"
git push -q origin "retry:$BR" 2>/dev/null \
  && ok "the landing's push goes through" \
  || fail "the push still fails after the reset"

echo "── a branch already merged is left alone"
git checkout -q main && git merge -q --no-ff -m merge retry && git push -q origin main 2>/dev/null
out="$(node "$tool" --branch "$BR" 2>&1)"
[[ "$out" == *"already in this history"* ]] || fail "a merged branch should be left alone, got: $out"
[ "$(git ls-remote --heads origin "$BR" | wc -l)" -eq 1 ] \
  || fail "a merged branch was deleted; the push would have fast-forwarded"
ok "a merged branch is kept — its push would fast-forward"

echo "── an unreachable remote is reported, not fatal"
git remote set-url origin "$tmp/does-not-exist"
out="$(node "$tool" --branch "$BR" 2>&1)"
[ $? -eq 0 ] && [[ "$out" == *"could not reach"* ]] \
  || fail "an unreachable remote must be best-effort, got: $out"
ok "a remote it cannot reach is reported and the landing still runs"

echo
if [ "$failures" -ne 0 ]; then echo "pen-reset.test.sh: $failures failure(s)" >&2; exit 1; fi
echo "pen-reset.test.sh: ok"
