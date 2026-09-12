#!/usr/bin/env bash
# A phase step's shell functions must not overwrite the step's path handles.
#
# Shell functions share the caller's variables unless a name is declared local,
# so a function that assigns `out=` is writing to the step's product-repo
# directory, not to a scratch of its own. Phase 01's `push_main` did exactly
# that:
#
#     push_main() {
#       out="$(git push -u origin main 2>&1)" && ...
#
# The push succeeded; the variable was ruined. The next line to use it,
# `land-pr.sh "$out" …`, ran `cd` on a git push transcript and failed with the
# transcript printed as a directory name, which reads as a fault inside
# land-pr.sh rather than a bad argument from its caller. A live build burned
# two identical attempts on it (the auto-retry could not help — nothing about
# it was transient).
#
# This is a whole-file static check rather than a behavioural one on purpose:
# the offending shell is embedded in a workflow's YAML and only runs with a
# real repo, a real remote and a real credential, so the thing that would have
# caught it cheaply is a reader that never gets bored. It costs no network and
# no fakes.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"

echo "── phase workflows: no function may reassign a step's path handle"
python3 - "$root" <<'PY'
import re, sys, pathlib

root = pathlib.Path(sys.argv[1])

# The handles a step sets once and depends on afterwards. Each names a
# DIRECTORY or a repo slug that later steps cd into or interpolate, so a
# function that rebinds one corrupts the rest of the step silently — there is
# no error at the point of the mistake.
RESERVED = {"out", "L", "P", "W", "slug", "remote_url"}

OPEN = re.compile(r"^(?P<indent>\s*)(?P<name>[A-Za-z_][A-Za-z0-9_]*)\(\)\s*\{\s*$")
ASSIGN = re.compile(r"^\s*(?P<var>[A-Za-z_][A-Za-z0-9_]*)=")

targets = sorted(root.glob("flows/phases/*/workflow.yaml")) + sorted(root.glob("flows/agent/*.yaml"))
if not targets:
    sys.exit("no phase workflows found — the glob or the layout changed")

problems = []
for path in targets:
    lines = path.read_text().splitlines()
    i = 0
    while i < len(lines):
        m = OPEN.match(lines[i])
        if not m:
            i += 1
            continue
        indent, fname, start = m.group("indent"), m.group("name"), i
        close = indent + "}"
        j = i + 1
        while j < len(lines) and lines[j] != close:
            a = ASSIGN.match(lines[j])
            if a and a.group("var") in RESERVED:
                problems.append(
                    f"{path.relative_to(root)}:{j + 1}: {fname}() assigns "
                    f"'{a.group('var')}' — that is the step's own handle; "
                    f"use a function-private name such as {fname.split('_')[0]}_{a.group('var')}"
                )
            j += 1
        if j >= len(lines):
            problems.append(
                f"{path.relative_to(root)}:{start + 1}: {fname}() has no closing "
                f"'{close}' at its own indent — this checker cannot read it"
            )
        i = j + 1

if problems:
    print("FAIL: a phase function reassigns a step handle:", file=sys.stderr)
    for p in problems:
        print(f"  - {p}", file=sys.stderr)
    sys.exit(1)

print(f"   {len(targets)} workflow(s) checked, no function reassigns a step handle")
PY

echo "── land-pr.sh refuses a first argument that is not a directory"
transcript="$(printf 'To https://github.com/a/b.git\n * [new branch]      main -> main')"
set +e
msg="$(bash "$root/flows/common/land-pr.sh" "$transcript" 01-scaffold "t" 2>&1)"
rc=$?
set -e
[ "$rc" -eq 2 ] || { echo "FAIL: expected exit 2 for a non-directory, got $rc" >&2; exit 1; }
printf '%s' "$msg" | grep -q "must be the product repo directory" \
  || { echo "FAIL: no argument diagnosis in: $msg" >&2; exit 1; }
printf '%s' "$msg" | grep -q "spans multiple lines" \
  || { echo "FAIL: multi-line value not called out in: $msg" >&2; exit 1; }
# The whole transcript must not be echoed back as if it were a path.
[ "$(printf '%s' "$msg" | wc -l)" -le 2 ] \
  || { echo "FAIL: diagnosis should be short, got: $msg" >&2; exit 1; }
echo "   refused with a one-line diagnosis naming the argument"

echo "phase-vars.test.sh: ok"
