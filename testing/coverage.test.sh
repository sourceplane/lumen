#!/usr/bin/env bash
# EVERY COMPONENT THIS REPO SHIPS IS PLACED BY EXACTLY ONE PHASE
# (saas-bootstrap-engine BE5, Tier 0; ported from cirrus).
#
# `repo-blueprint.yaml` decides what a product is made of. A component that no
# module names is not a component a product gets — and nothing would say so.
# The failure is quiet and late: the fork builds, its CI goes green, and the
# missing piece surfaces when somebody looks for a worker that was never
# copied.
#
# orun already enforces the other half — every MODULE belongs to exactly one
# phase, and a module naming an unknown module is a parse error. What it cannot
# know is what this repository contains, because a blueprint declares what to
# place and not what exists. That is this file's job.
#
# bash + python3 + PyYAML. No network, no orun, no credential.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"

echo "── every component against the blueprint that places it"
python3 - "$root" <<'PY'
import pathlib, sys

try:
    import yaml
except ImportError:
    sys.exit("PyYAML is required for the coverage gate (pip install pyyaml)")

root = pathlib.Path(sys.argv[1])
problems = []
def bad(m): problems.append(m)

# A component directory this repository deliberately keeps to itself. Declared
# with its reason rather than skipped by a pattern: "tests/*" would also hide
# the thirteen component test suites a product genuinely needs, and the next
# baseline-only directory should have to be argued for in a diff.
# EMPTY, and that is the milestone's own result rather than an oversight. The
# one candidate was `tests/flows`, the bootstrap's contract suite, exempt
# because it tested `flows/` — which no product carried. `flows/` is gone, its
# suite is gone with it, and the gates that replace it live in `testing/`
# (which is not a component at all, and so is not a component this gate can
# miss).
#
# The map stays rather than the mechanism being deleted with no entry: the
# check below refuses an exemption whose directory is absent, so a stale entry
# cannot linger — and the next baseline-only directory should still have to be
# argued for in a diff rather than discovered as a re-added feature.
BASELINE_ONLY: dict[str, str] = {}

bp = yaml.safe_load((root / "repo-blueprint.yaml").read_text())

# Where each module takes its content from, and which phase places it.
placed_by = {}
for m in bp.get("modules") or []:
    src = (m.get("from") or "").rstrip("/")
    if src:
        placed_by.setdefault(src, []).append(m["name"])
phase_of = {n: ph["name"] for ph in (bp.get("phases") or []) for n in ph["modules"]}

components = sorted(
    p.parent.relative_to(root).as_posix()
    for p in root.rglob("component.yaml")
    if "node_modules" not in p.parts and ".git" not in p.parts
)
if not components:
    sys.exit("no component.yaml anywhere — this check has gone blind")

for comp in components:
    modules = placed_by.get(comp, [])
    reason = BASELINE_ONLY.get(comp)

    if reason and modules:
        bad(f"{comp} is declared baseline-only ({reason}) and yet {modules[0]} "
            f"places it — one of the two is wrong")
        continue
    if reason:
        continue
    if not modules:
        bad(f"{comp} is a component and no module places it. Either add one, or "
            f"declare it baseline-only in this file with the reason.")
        continue
    if len(modules) > 1:
        bad(f"{comp} is placed by {len(modules)} modules ({', '.join(modules)}) "
            f"— a component comes from one place")
        continue
    if modules[0] not in phase_of:
        bad(f"{comp} is placed by {modules[0]}, which is in no phase")

# The other direction: a module naming a path this repo does not have places
# nothing, silently. orun resolves `from` against the source tree and an absent
# path is an empty module, not an error.
for src, modules in sorted(placed_by.items()):
    if not (root / src).exists():
        bad(f"module {modules[0]} takes its content from {src}, which does not "
            f"exist — it would place nothing, and say nothing")

# A directory named baseline-only must actually BE one, or the exemption is
# protecting nothing and will outlive the thing it was written for.
for comp in BASELINE_ONLY:
    if not (root / comp).exists():
        bad(f"{comp} is declared baseline-only and does not exist — drop the entry")

# ── WHAT `ignore` ACTUALLY EXCLUDES (BE6) ──────────────────────────────────
#
# orun matches an ignore entry two ways, and WHICH ONE depends on the entry:
# a pattern containing no glob metacharacter is compared against each path
# SEGMENT, and only a pattern containing one is compared against the whole
# relative path. So `apps/admin-worker/wrangler.jsonc` matches nothing at all —
# no segment is ever equal to it — and the entry is INERT while reading exactly
# like a rule.
#
# That was not hypothetical. Twelve such entries were inert in cirrus's
# blueprint, copied from this one, and a canary written to `apps/admin-worker/wrangler.jsonc` was
# placed straight into a product — which is the leak their comment says they
# exist to prevent. An `ignore` list that silently does nothing is worse than
# no list, because the comment above it reads as a defence.
for entry in bp.get("ignore") or []:
    if "/" in entry and not any(c in entry for c in "*?["):
        bad(f'ignore entry "{entry}" names a path and has no glob character, so orun '
            f'matches it against path SEGMENTS and it excludes nothing. Write it as '
            f'"**/{entry}".')

# A workflow that runs the FACTORY must not ship to the factory's products.
# `github-workflows` copies the whole `.github` directory, so a lane added for
# this repository travels to every product built from it — and one that reads a
# path under `testing/` cannot work there, because `testing/` is not placed.
# ci.yml did exactly this here: its `flows-contract` job ran the factory's
# contract suite, and every product got a job that is red on its first PR.
ignored = set(bp.get("ignore") or [])
workflows = sorted((root / ".github" / "workflows").glob("*.y*ml"))
for wf in workflows:
    text = wf.read_text(encoding="utf-8")
    if "testing/" not in text:
        continue
    rel = f".github/workflows/{wf.name}"
    if f"**/{rel}" not in ignored and rel not in ignored:
        bad(f"{rel} reads a path under testing/, which no product is placed with, "
            f"and is not in the blueprint's ignore list — so it ships into every "
            f'product and fails there. Add "**/{rel}" to ignore.')

if problems:
    print("FAIL: the blueprint and this repository disagree about what a product is:",
          file=sys.stderr)
    for p in problems:
        print(f"  - {p}", file=sys.stderr)
    sys.exit(1)

shipped = len(components) - len(BASELINE_ONLY)
print(f"   {shipped} of {len(components)} components placed, "
      f"{len(BASELINE_ONLY)} baseline-only by declaration")
PY

echo "coverage.test.sh: ok"
