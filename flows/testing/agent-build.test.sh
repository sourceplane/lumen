#!/usr/bin/env bash
# The contract test for flows/agent/build.sh — the sandbox agent's one command
# — over the fake orun and a fake gh (no network, no credential). Claims:
#   1. the runner reads workspace, repository and checkout from the
#      environment the platform prepared and passes them to the umbrella —
#      the agent retypes nothing beyond the three intake values;
#   2. every phase completion becomes one UPDATE line, and success ends in
#      DONE plus a summary;
#   3. a failed phase ends in FAILED with the re-run instruction, and an
#      operator action surfaces as the one ACTION REQUIRED line;
#   4. a missing credential is an ACTION REQUIRED before anything runs;
#   5. the runner never prints a token.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
build="$root/flows/agent/build.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

# A product checkout whose origin names the bound repository.
mkdir -p "$tmp/work" && git init -q "$tmp/work/widget" && git -C "$tmp/work/widget" remote add origin https://github.com/acme/widget.git
mkdir -p "$tmp/work/widget/ai/context" && : > "$tmp/work/widget/ai/context/deployment.md"
printf '{"repoName":"widget","workersDevSubdomain":"acme"}\n' > "$tmp/vals.json"
mkdir -p "$tmp/work/widget/.rebrand" && cp "$tmp/vals.json" "$tmp/work/widget/.rebrand/values.json"
# A fake gh on PATH so the runner installs nothing.
mkdir -p "$tmp/bin" && printf '#!/usr/bin/env bash\necho "gh version 2.0.0"\n' > "$tmp/bin/gh" && chmod +x "$tmp/bin/gh"
# A fake curl so the summary's endpoint probe answers 200 without a network.
printf '#!/usr/bin/env bash\necho 200\n' > "$tmp/bin/curl" && chmod +x "$tmp/bin/curl"
export PATH="$tmp/bin:$here/fake-orun:$PATH" FAKE_ORUN_STATE="$tmp/state.json" TRACK_WORKDIR="$tmp/run" HOME="$tmp/home"
mkdir -p "$TRACK_WORKDIR" "$HOME"
export ORUN_WORKSPACE=ws_TEST ORUN_REPO_FULL_NAME=acme/widget GITHUB_TOKEN=ghs_SECRET_TOKEN_VALUE ORUN_TOKEN_FILE="$tmp/tok"
printf 'orun_SECRET_TOKEN_VALUE' > "$tmp/tok"
run() { (cd "$tmp/work/widget" && "$build" --product-name "Acme Cloud" --product-domain acme.dev --subdomain acme "$@" >"$tmp/out" 2>&1); echo $?; }

echo "── 1+2. environment in, UPDATE lines and DONE out"
rc="$(run)"; [ "$rc" = 0 ] || { cat "$tmp/out"; fail "expected exit 0, got $rc"; }
grep -q '^UPDATE: starting the Acme Cloud build into acme/widget (workspace ws_TEST)' "$tmp/out" || fail "no start line: $(cat "$tmp/out")"
[ "$(grep -c '^UPDATE: ' "$tmp/out")" = 8 ] || fail "expected 8 UPDATE lines (start + 7 phases), got $(grep -c '^UPDATE: ' "$tmp/out"): $(grep '^UPDATE' "$tmp/out")"
grep -q '^UPDATE: the console is live on stage and prod$' "$tmp/out" || fail "console phase not narrated"
grep -q '^DONE$' "$tmp/out" || fail "no DONE"
grep -q '^── Summary: Acme Cloud (acme/widget)' "$tmp/out" || fail "no summary"
grep -q '^duration: ' "$tmp/out" || fail "no duration"
python3 - "$FAKE_ORUN_STATE" "$tmp/work/widget" <<'PY' || fail "umbrella wire"
import json,sys; st=json.load(open(sys.argv[1])); c=[c for c in st["calls"] if c[:2]==["workflow","run"]][0]
sets={a.split("=",1)[0]:a.split("=",1)[1] for a in c if "=" in a and not a.startswith("--")}
assert c[2].endswith("/flows/phases/00-all/workflow.yaml"), c[2]
assert sets["workspace"]=="ws_TEST" and sets["reponame"]=="widget" and sets["githuborg"]=="acme", sets
assert sets["out"]==sys.argv[2] and sets["watch"]=="auto" and sets["track"]=="true", sets
assert sets["productname"]=="Acme Cloud" and sets["productdomain"]=="acme.dev" and sets["subdomain"]=="acme", sets
PY
grep -q 'SECRET_TOKEN_VALUE' "$tmp/out" && fail "a token reached the output" || true

echo "── 3. a failed phase → FAILED with the re-run rule; an operator action → ACTION REQUIRED"
rc="$(FAKE_ORUN_UMBRELLA=fail run)"; [ "$rc" = 1 ] || fail "expected exit 1 on a failed phase, got $rc"
grep -q '^FAILED: 03-infrastructure did not complete' "$tmp/out" || fail "no FAILED line: $(tail -5 "$tmp/out")"
grep -q 'run this same command again' "$tmp/out" || fail "no re-run instruction"
grep -q 'not allow-listed' "$tmp/out" || fail "the phase's own message was swallowed"
rc="$(FAKE_ORUN_UMBRELLA=action run)"; [ "$rc" = 3 ] || fail "expected exit 3 on an operator action, got $rc"
[ "$(grep -c '^ACTION REQUIRED: ' "$tmp/out")" = 2 ] || fail "ACTION REQUIRED should pass through once and be restated once: $(grep -c '^ACTION REQUIRED: ' "$tmp/out")"
grep -q '^FAILED' "$tmp/out" && fail "an operator action must not also read as FAILED" || true

echo "── 4. a missing credential stops before the build"
rc="$(GITHUB_TOKEN= GH_TOKEN= run)"; [ "$rc" = 3 ] || fail "expected exit 3 without a GitHub credential, got $rc"
grep -q '^ACTION REQUIRED: the GitHub credential is missing' "$tmp/out" || fail "wrong message: $(cat "$tmp/out")"
[ "$(python3 -c 'import json,sys;print(len([c for c in json.load(open(sys.argv[1]))["calls"] if c[:2]==["workflow","run"]]))' "$FAKE_ORUN_STATE")" = 3 ] || fail "the umbrella ran without a credential"

echo "── 5. an old binary stops before the build"
rc="$(FAKE_ORUN_VERSION=2.54.0 run)"; [ "$rc" = 1 ] || fail "expected exit 1 on an old binary, got $rc"
grep -q '^FAILED: orun 2.54.0 is older than the 2.55.0' "$tmp/out" || fail "wrong message: $(cat "$tmp/out")"

echo "agent-build.test.sh: all claims hold"
