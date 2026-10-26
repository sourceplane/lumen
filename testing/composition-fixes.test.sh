#!/usr/bin/env bash
# THE IN-TREE COMPOSITION IS THE PUBLISHED ONE PLUS ITS FIX, AND NOTHING ELSE.
#
# `stack-tectonic-fixes/` holds stack-tectonic 0.20.0's `turbo-package` with
# three guards corrected (`{{if .preBuildCommand}}` → `{{if
# .parameters.preBuildCommand}}`, and the same for build and typecheck), and
# `intent.yaml` binds that one composition type to it. A vendored copy is how
# execution contracts drift: somebody edits it to fix a product, and the
# product now runs something no release of stack-tectonic contains. This gate
# keeps the copy to exactly the published files plus that fix:
#
#   1. undo the three fixes and every file must hash to what 0.20.0 published
#      (`upstream-<version>.sha256`, recorded from the OCI artifact);
#   2. the pin in `intent.yaml` must still be that version, so moving the pin
#      is when somebody has to decide whether the copy is still needed;
#   3. the binding, the source and the blueprint module must all be present,
#      and the module must land in the phase that lands `intent.yaml`, since
#      that file names the directory;
#   4. once the directory is deleted, nothing may still name it.
#
# bash + python3 + PyYAML. No network, no orun, no credential.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"

echo "── the in-tree turbo-package against the release it patches"
python3 - "$root" <<'PY'
import hashlib, pathlib, re, sys

try:
    import yaml
except ImportError:
    sys.exit("PyYAML is required for this gate (pip install pyyaml)")

root = pathlib.Path(sys.argv[1])
fixes = root / "stack-tectonic-fixes"
NAME = "stack-tectonic-fixes"
problems = []
def bad(m): problems.append(m)

intent = yaml.safe_load((root / "intent.yaml").read_text())
comp = intent.get("compositions") or {}
sources = {s["name"]: s for s in comp.get("sources") or []}
bindings = (comp.get("resolution") or {}).get("bindings") or {}
bp = yaml.safe_load((root / "repo-blueprint.yaml").read_text())
modules = {m["name"]: m for m in bp.get("modules") or []}
phase_of = {n: ph["name"] for ph in bp.get("phases") or [] for n in ph.get("modules") or []}

if not fixes.is_dir():
    # Deleted, as its README asks once upstream ships the fix. Then nothing
    # may still point at it: a product's intent naming a directory it never
    # received fails its first plan.
    if NAME in sources:
        bad(f"intent.yaml still declares the {NAME} source, and the directory is gone")
    stale = sorted(t for t, s in bindings.items() if s == NAME)
    if stale:
        bad(f"intent.yaml still binds {stale} to {NAME}, and the directory is gone")
    if NAME in modules:
        bad(f"repo-blueprint.yaml still has a {NAME} module, and the directory is gone")
    if problems:
        print("\n".join(f"FAIL: {p}" for p in problems), file=sys.stderr)
        sys.exit(1)
    print("   no in-tree compositions, and nothing names one")
    sys.exit(0)

# ── which release it patches ───────────────────────────────────────────────
records = sorted(fixes.glob("upstream-*.sha256"))
if len(records) != 1:
    sys.exit(f"FAIL: want exactly one upstream-<version>.sha256 in {NAME}/, found {len(records)}")
version = records[0].name[len("upstream-"):-len(".sha256")]
recorded = {}
for line in records[0].read_text().splitlines():
    if line.strip():
        digest, path = line.split(None, 1)
        recorded[path.strip()] = digest
if not recorded:
    sys.exit(f"FAIL: {records[0].name} records no files — this check has gone blind")

upstream = sources.get("stack-tectonic") or {}
ref = upstream.get("ref", "")
if not ref.endswith(f":{version}"):
    bad(f"intent.yaml pins stack-tectonic at {ref!r}, but {NAME}/ patches {version}. "
        f"Moving the pin is the moment to decide: if the new release reads "
        f".parameters.* in turbo-package's guards, delete {NAME}/ as its README "
        f"says; if not, copy turbo-package from the new release, reapply the "
        f"three fixes and record its hashes as upstream-<new>.sha256")

# ── wired: the source, the binding, the module, the phase ──────────────────
src = sources.get(NAME)
if not src:
    bad(f"intent.yaml does not declare the {NAME} source, so the copy is dead")
elif src.get("kind") != "dir" or src.get("path") != NAME:
    bad(f"the {NAME} source must be kind: dir, path: {NAME} (is {src.get('kind')!r}, {src.get('path')!r})")
if bindings.get("turbo-package") != NAME:
    bad(f"intent.yaml does not bind turbo-package to {NAME}, so the published "
        f"composition still wins and pre-build still skips itself")

stack = yaml.safe_load((fixes / "stack.yaml").read_text())
exported = sorted(pathlib.PurePosixPath(e["path"]).parent.name
                  for e in (stack.get("spec") or {}).get("compositions") or [])
if exported != ["turbo-package"]:
    bad(f"{NAME}/stack.yaml exports {exported}; it is for turbo-package alone — "
        f"any other fix belongs upstream, or in an argued diff to this gate")
others = sorted(t for t, s in bindings.items() if s == NAME and t != "turbo-package")
if others:
    bad(f"intent.yaml binds {others} to {NAME}, which exports only turbo-package")

mod = modules.get(NAME)
if not mod:
    bad(f"no blueprint module places {NAME}/ — every product's intent names it, "
        f"so every product's first plan would fail")
else:
    if (mod.get("from"), mod.get("to")) != (NAME, NAME):
        bad(f"module {NAME} copies {mod.get('from')!r} → {mod.get('to')!r}, not {NAME} → {NAME}")
    if phase_of.get(NAME) != phase_of.get("root-intent"):
        bad(f"module {NAME} lands in {phase_of.get(NAME)}, but intent.yaml (which "
            f"names it) lands in {phase_of.get('root-intent')}; between the two, "
            f"the product cannot plan")

# ── the files: the published ones, plus the three fixes, plus nothing ──────
FIXES = [(f"{{{{if .{k}}}}}", f"{{{{if .parameters.{k}}}}}")
         for k in ("preBuildCommand", "buildCommand", "typecheckCommand")]
JOB = "compositions/turbo-package/jobs/turbo-package-verify.yaml"
present = sorted(p.relative_to(fixes).as_posix() for p in fixes.rglob("*")
                 if p.is_file() and p.relative_to(fixes).parts[0] == "compositions")
for extra in sorted(set(present) - set(recorded)):
    bad(f"{NAME}/{extra} is not a file {version} published")
for missing in sorted(set(recorded) - set(present)):
    bad(f"{NAME}/{missing} is missing — {version} published it")

for rel in sorted(set(present) & set(recorded)):
    text = (fixes / rel).read_text()
    if rel == JOB:
        for broken, fixed in FIXES:
            n = text.count(fixed)
            if n != 1:
                bad(f"{rel} carries {fixed!r} {n} time(s), want exactly 1")
            text = text.replace(fixed, broken)
    if hashlib.sha256(text.encode()).hexdigest() != recorded[rel]:
        bad(f"{NAME}/{rel} differs from {version} by more than the three guard "
            f"fixes. The copy is not a place to change what a step does: make the "
            f"change in sourceplane/stack-tectonic")

# Every guard in the job reads a namespace orun's template context has. This
# is the bug itself, stated as a rule, so a re-copy from a later release that
# still has it fails here rather than in a lane that quietly skips its tests.
NAMESPACES = {"orun", "parameters", "env"}
job = (fixes / JOB).read_text()
for key in re.findall(r"\{\{-?\s*if\s+\.([A-Za-z_]\w*)", job):
    if key not in NAMESPACES:
        bad(f"{JOB} guards on .{key}, which orun's template context does not "
            f"have (it has .orun, .parameters and .env) — that step always takes "
            f"its else branch")

if problems:
    print("\n".join(f"FAIL: {p}" for p in problems), file=sys.stderr)
    sys.exit(1)
print(f"   turbo-package is {version} plus its three guard fixes, bound, and "
      f"placed with the intent ({phase_of.get(NAME)})")
PY
