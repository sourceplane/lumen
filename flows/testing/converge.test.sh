#!/usr/bin/env bash
# The contract test for flows/common/converge.sh and ghrest's resume helper.
#
# THE FAILURE THIS EXISTS FOR. A live cirrus build failed phase 02-foundation
# three times and told its operator exactly this:
#
#     ✕ run: /bin/bash exited 22:
#
# Nothing else. Exit 22 is `curl -f` meeting an HTTP error; the body was
# discarded by `-s`, `gh`'s stderr by `2>/dev/null`, and `set -e` then killed
# converge.sh before it could list the failed lanes. The convergence had
# already failed for some other reason — and that reason was now unreachable.
#
# So: a resume GitHub refuses must (1) say why, and (2) never replace the
# diagnosis with a bare exit code. Both are asserted below against a fake
# GitHub that refuses the rerun the way the real one did.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

# A gh that knows the run and refuses to rerun it, plus a curl that answers
# 403 the way GitHub's rerun-failed-jobs endpoint does, and a sleep that does
# not. On PATH ahead of the real ones.
mkdir -p "$tmp/bin"
cat > "$tmp/bin/gh" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  # `ghr_run_field` calls gh with --jq, so the BARE value comes back, not JSON.
  "run view "*"--json status"*)     echo completed; exit 0 ;;
  "run view "*"--json conclusion"*) echo failure;   exit 0 ;;
  "run view "*"--json jobs"*)       printf 'build (stage)\nbuild (prod)\n'; exit 0 ;;
  "run rerun"*) echo "HTTP 403: Unable to retry this run (rerun-failed-jobs)" >&2; exit 1 ;;
esac
exit 1
EOF
cat > "$tmp/bin/curl" <<'EOF'
#!/usr/bin/env bash
# Only the rerun endpoint is exercised, and `-f` is honoured EXACTLY as real
# curl honours it — silence, exit 22 — because that is the whole bug: the old
# code called this through `ghr_curl`, which passes `-sf`, so a 403 arrived as
# a bare status 22 with the body thrown away. A fake that answered 200-with-a-
# body would let the broken code pass.
fail=0
for a in "$@"; do case "$a" in -sf|-f|-fs) fail=1 ;; esac; done
for a in "$@"; do case "$a" in *rerun-failed-jobs)
  [ "$fail" = 1 ] && exit 22
  printf '{"message":"Unable to retry this workflow run because it was not attempted with failed jobs.","status":"403"}\n403'
  exit 0 ;; esac; done
exit 1
EOF
printf '#!/usr/bin/env bash\nexit 0\n' > "$tmp/bin/sleep"
chmod +x "$tmp/bin/gh" "$tmp/bin/curl" "$tmp/bin/sleep"
export PATH="$tmp/bin:$PATH" GH_TOKEN=fake GH_REPO=acme/product

echo "── 1. a refused resume reports WHY, and still lists the failed lanes"
set +e
out="$(timeout 30 "$root/flows/common/converge.sh" 34773962565 3 2>&1)"; rc=$?
set -e

[ "$rc" -ne 0 ] || fail "expected a non-zero exit, got 0: $out"
# converge.sh polls until the run is terminal; a hang here is a regression in
# its own right, not a slow test.
[ "$rc" -ne 124 ] || fail "converge.sh never terminated (timed out): $out"
# The bug: exit 22 straight out of curl, with no output at all.
[ "$rc" -ne 22 ] || fail "still exiting 22 from curl — the resume failure is unhandled: $out"
echo "$out" | grep -q "resuming failed lanes (1/3)" || fail "no resume attempt line: $out"
echo "$out" | grep -qi "403" || fail "the HTTP status is not reported: $out"
echo "$out" | grep -q "not attempted with failed jobs" \
  || echo "$out" | grep -q "Unable to retry" \
  || fail "GitHub's own words are not reported: $out"
echo "$out" | grep -q "resume could not be issued" || fail "no plain-words explanation: $out"
# The part an operator actually needs, which the old path never reached.
echo "$out" | grep -q "failed lanes:" || fail "the failed-lane listing is missing: $out"
echo "$out" | grep -q "build (stage)" || fail "the failed lane names are missing: $out"
echo "   a refused resume: reason + failed lanes, exit $rc"

echo "── 2. a green run still exits 0 without touching the resume path"
cat > "$tmp/bin/gh" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  "run view "*"--json status"*)     echo completed; exit 0 ;;
  "run view "*"--json conclusion"*) echo success;   exit 0 ;;
  "run rerun"*) echo "the resume path must not be reached on a green run" >&2; exit 1 ;;
esac
exit 1
EOF
chmod +x "$tmp/bin/gh"
out="$(timeout 30 "$root/flows/common/converge.sh" 34773962565 3 2>&1)" || fail "green run should exit 0: $out"
echo "$out" | grep -q "✓ convergence green" || fail "no green line: $out"
echo "   a green convergence is unchanged"

echo "converge.test.sh: ok"
