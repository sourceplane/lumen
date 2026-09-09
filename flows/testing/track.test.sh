#!/usr/bin/env bash
# The BT1 contract test for flows/common/track.sh, against the fake orun in
# flows/testing/fake-orun (no network, no credential). Claims:
#   1. a first run creates the epic, the phase's milestone and the landing's
#      task, and prints the key;
#   2. a second run creates NOTHING and prints the same handles (idempotent
#      by identity — a cleared cache still finds them on the plane);
#   3. an orun that predates the task-plane verbs degrades to "untracked":
#      one line on stderr, an empty stdout, exit 0 — never a failed landing.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
track="$root/flows/common/track.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export PATH="$here/fake-orun:$PATH" FAKE_ORUN_STATE="$tmp/state.json" TRACK_WORKDIR="$tmp/run" ws=ws_TEST
mkdir -p "$TRACK_WORKDIR"
fail() { echo "FAIL: $*" >&2; exit 1; }
calls() { python3 -c 'import json,sys;print(len(json.load(open(sys.argv[1]))["calls"]))' "$FAKE_ORUN_STATE"; }
# Objects on the plane (epics + milestones + tasks): what a re-run must not grow.
creates() { python3 -c 'import json,sys;s=json.load(open(sys.argv[1]));print(len(s["epics"])+len(s["milestones"])+len(s["tasks"]))' "$FAKE_ORUN_STATE"; }
contract="$root/flows/phases/03-infrastructure/task-contract.yaml"
title="phase(03-infrastructure): d1, kv, db-migrate"

echo "── 1. first run creates"
slug="$("$track" ensure-epic infra-baselining "Infra baselining — Acme" "Bootstrap of sourceplane/acme" 2>"$tmp/err1")"
[ "$slug" = infra-baselining ] || fail "ensure-epic printed '$slug'"
key="$("$track" ensure-task infra-baselining 03-infrastructure "$title" "$contract" "Land the data plane." 2>>"$tmp/err1")"
[ "$key" = BASE-1 ] || fail "ensure-task printed '$key'"
grep -q "epic infra-baselining created" "$tmp/err1" || fail "epic create not narrated: $(cat "$tmp/err1")"
grep -q 'milestone "03 — infrastructure" created' "$tmp/err1" || fail "milestone create not narrated"
grep -q "task BASE-1 created" "$tmp/err1" || fail "task create not narrated"
[ "$(creates)" = 3 ] || fail "expected 3 creates, saw $(creates)"
python3 - "$FAKE_ORUN_STATE" <<'PY' || fail "task create wire"
import json,sys; st=json.load(open(sys.argv[1])); c=[c for c in st["calls"] if c[:2]==["task","create"]][0]
assert "--epic" in c and "--milestone" in c and "--assignee" in c and c[c.index("--assignee")+1]=="me" and "--contract" in c and "--prefix" in c, c
m=st["milestones"][0]; assert m["exitCriteria"]==["WIRING_CLOUDFLARE_KV, WIRING_CLOUDFLARE_HYPERDRIVE and SUPABASE_PROJECT_REF published on stage and prod"], m
PY
rollup="$("$track" rollup infra-baselining 2>/dev/null)"
[ "$rollup" = "0/1 done · 03 — infrastructure: 0/1" ] || fail "rollup printed '$rollup'"
v="$("$track" verdict BASE-1 2>/dev/null)"
[ "$v" = "ready — contract complete" ] || fail "verdict printed '$v'"

echo "── 2. second run reuses (cache cleared: identity, not memory)"
rm -f "$TRACK_WORKDIR/tracking.json"
before="$(creates)"
slug="$("$track" ensure-epic infra-baselining "Infra baselining — Acme" 2>"$tmp/err2")"
key2="$("$track" ensure-task infra-baselining 03-infrastructure "$title" "$contract" 2>>"$tmp/err2")"
[ "$slug" = infra-baselining ] && [ "$key2" = "$key" ] || fail "second run printed '$slug' / '$key2'"
[ "$(creates)" = "$before" ] || fail "second run created something: $(creates) vs $before"
grep -q "already exists — reusing" "$tmp/err2" && grep -q 'milestone "03 — infrastructure" exists' "$tmp/err2" && grep -q "task BASE-1 exists" "$tmp/err2" \
  || fail "reuse not narrated: $(cat "$tmp/err2")"
echo "── 2b. a second landing in the same phase is a second task, same milestone"
key3="$("$track" ensure-task infra-baselining 03-infrastructure "phase(03-infrastructure): a second landing" "$contract" 2>/dev/null)"
[ "$key3" = BASE-2 ] || fail "second landing printed '$key3'"
[ "$(python3 -c 'import json,sys;print(len(json.load(open(sys.argv[1]))["milestones"]))' "$FAKE_ORUN_STATE")" = 1 ] || fail "milestone duplicated"

echo "── 3. an old binary degrades to untracked"
rm -f "$TRACK_WORKDIR/tracking.json"
out="$(FAKE_ORUN_OLD=1 "$track" ensure-task infra-baselining 03-infrastructure "$title" "$contract" 2>"$tmp/err3")" || fail "old binary must exit 0"
[ -z "$out" ] || fail "old binary printed a handle: '$out'"
grep -q "predates the task-plane verbs" "$tmp/err3" || fail "refusal not narrated: $(cat "$tmp/err3")"
FAKE_ORUN_OLD=1 "$track" ensure-epic x "X" 2>"$tmp/err3b" >/dev/null
[ ! -s "$tmp/err3b" ] || fail "refusal narrated twice"
echo "── 3b. no workspace degrades the same way"
out="$(ws= "$track" ensure-epic x "X" 2>/dev/null)" && [ -z "$out" ] || fail "no-workspace must be empty + exit 0"
echo "track.test.sh: all claims hold"
