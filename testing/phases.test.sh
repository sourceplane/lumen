#!/usr/bin/env bash
# The phases in `repo-blueprint.yaml` must be the phases the bootstrap runs
# (saas-bootstrap-engine BE1, ported from cirrus).
#
# Before BE1 this could not be checked, because the two were different
# documents: `tooling/blueprint/split-phases.py` derived eight
# `flows/phases/*/blueprint.yaml` slices from this file and re-mapped their
# names to folders through a table inside the script. A mapping table in a
# generator is a fact nothing compares to anything, and it was wrong — this
# file declared `workspace` last while the folder it became, `01-scaffold`,
# runs first.
#
# THE PARTITION BELOW IS THE PRE-MIGRATION TRUTH. It is what the eight slices
# actually placed, read off them at the commit that deleted them. Its job is to
# fail if a later edit quietly moves a module between phases: the bootstrap's
# order is load-bearing (a worker cannot deploy before its Hyperdrive exists)
# and a module that drifts one phase earlier fails at deploy time, live, with
# nothing in this repo having looked wrong.
#
# bash + python3 + PyYAML. No network, no fakes, no credential.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"

echo "── repo-blueprint.yaml phases against what the bootstrap runs"
python3 - "$root" <<'PY'
import pathlib, re, sys

try:
    import yaml
except ImportError:
    sys.exit("PyYAML is required for the phase contract test (pip install pyyaml)")

root = pathlib.Path(sys.argv[1])
problems = []
def bad(m): problems.append(m)

bp = yaml.safe_load((root / "repo-blueprint.yaml").read_text())
phases = bp.get("phases") or []
if not phases:
    sys.exit("repo-blueprint.yaml declares no phases — this check has gone blind")

# What the eight slices placed, before they were deleted.
WAS = {
    # `ai-context` became `ai-deployment` + `ai-operations`: the module copied
    # the whole of ai/context/, which carried this repository's own planning
    # state (current.md, decisions.md, open-risks.md) into every product. The
    # partition below is the pre-migration truth for everything else; this
    # line and the 03 split below are deliberate, argued changes and are
    # recorded as such.
    "01-scaffold": ["ai-deployment", "ai-operations", "github-workflows", "rebrand-values", "root-gitignore",
                    "root-intent", "root-kiox", "root-kiox-lock", "root-package-json",
                    "root-pnpm-lock", "root-pnpm-workspace", "root-readme", "root-turbo",
                    "tooling-eslint", "tooling-tsconfig", "tooling-wire", "vscode"],
    "02-foundation": ["cli", "contracts", "contracts-tests", "db", "db-tests",
                      "notifications-client", "notifications-client-tests", "policy-engine",
                      "policy-engine-tests", "sdk", "shared", "testing", "webhook-verifier"],
    # The slice placed all four data-plane modules and landed without waiting,
    # because two of them could never pass on the PR: hyperdrive and db-migrate
    # plan against supabase's job outputs, which exist only after the apply on
    # main. They moved to `03-infrastructure-database`, which runs after that
    # apply, so every phase's PR can be verified before it merges.
    "03-infrastructure": ["cloudflare-kv", "supabase"],
    "03-infrastructure-database": ["cloudflare-hyperdrive", "db-migrate"],
    "04-workers": ["admin-worker", "admin-worker-tests", "billing-worker", "billing-worker-tests",
                   "config-worker", "config-worker-tests", "events-worker", "events-worker-tests",
                   "identity-worker", "identity-worker-tests", "integrations-worker",
                   "integrations-worker-tests", "membership-worker", "membership-worker-tests",
                   "metering-worker", "metering-worker-tests", "notifications-worker",
                   "notifications-worker-tests", "policy-worker", "policy-worker-tests",
                   "projects-worker", "projects-worker-tests", "webhooks-worker",
                   "webhooks-worker-tests"],
    "05-edge": ["api-edge", "api-edge-tests"],
    "06-console": ["web-console-next", "web-console-next-tests"],
    "07-domain": ["cloudflare-domain"],
}
# Declared since BE1 and placing nothing: their work is hooks. `discovery-roots`
# is likewise new — the empty apps/infra/packages/tests roots orun's repo-scale
# gate requires, which the scaffold flow used to create with a mkdir.
# `platform-limits-tests` is likewise new here: a component the baseline grew
# after the slices were cut, which no slice placed (the coverage gate found it).
ADDED = {"01-scaffold": ["discovery-roots"], "05-edge": ["platform-limits-tests"]}
HOOK_ONLY = {"04-workers-restore", "08-docs"}

by_name = {p["name"]: p for p in phases}
names = [p["name"] for p in phases]

# ── the order IS the execution order ──────────────────────────────────────
if names != sorted(names):
    bad(f"phases are not in execution order: {names}. The numbered name IS the "
        f"order; a phase out of sequence is a barrier in the wrong place.")

# ── the partition has not drifted ─────────────────────────────────────────
for name, was in WAS.items():
    if name not in by_name:
        bad(f"phase {name} is gone — the bootstrap ran it before BE1")
        continue
    now = sorted(by_name[name].get("modules") or [])
    want = sorted(was + ADDED.get(name, []))
    if now != want:
        moved_in = sorted(set(now) - set(want))
        moved_out = sorted(set(want) - set(now))
        bad(f"phase {name} no longer places what it placed: "
            f"gained {moved_in or '[]'}, lost {moved_out or '[]'}")

for name in HOOK_ONLY:
    if name not in by_name:
        bad(f"phase {name} is missing")
    elif by_name[name].get("modules"):
        bad(f"phase {name} places modules — it is declared as hooks only")

# ── nothing may GATE on a phase the tree cannot answer for ────────────────
#
# A hook-only phase places no files, so orun derives it as `unknown` rather
# than `done` (orun BE-O10) — deliberately, because its work is a landing in
# the task plane and a live deployment, neither of which the product repo can
# be asked about. `requires.phases` fails closed on `unknown`. So a requirement
# naming one can NEVER be satisfied, and the phase declaring it refuses for the
# whole of a real bootstrap.
#
# BE1 shipped exactly that: `05-edge` required `04-workers-restore`, and the
# epic's own open question 7 said "nothing declares one on them" — true of the
# intent, false of the file, with nothing comparing the two. It surfaced only
# once orun BE-O12 made the phases before it pass:
#
#     ✕ phase "05-edge" requires 04-workers-restore (unknown)
#
# Naming the hook-only phase's own predecessor instead loses no ordering: phase
# order in this document is what sequences a run, and `requires` is the gate
# that catches a phase run against a tree where its predecessor never happened.
for p in phases:
    for need in ((p.get("requires") or {}).get("phases") or []):
        if need in HOOK_ONLY:
            bad(f"phase {p['name']} requires {need}, which places no files — orun "
                f"derives a hook-only phase as `unknown` and requires.phases "
                f"fails closed on it, so this gate can never pass. Require its "
                f"predecessor instead.")

# ── every phase says what it is and what to budget ────────────────────────
for p in phases:
    for field in ("title", "expectedMinutes"):
        if not p.get(field):
            bad(f"phase {p['name']} declares no {field} — an operator reads both")
    if not (p.get("hooks") or {}):
        bad(f"phase {p['name']} declares no hooks — a phase that only places "
            f"files still has to land them")

# ── every contract a hook names exists ────────────────────────────────────
def hooks_of(p):
    h = p.get("hooks") or {}
    if isinstance(h, list):
        return list(h)
    return [x for slot in ("pre", "post", "await") for x in (h.get(slot) or [])]

for p in phases:
    for h in hooks_of(p) + [x for x in ((p.get("requires") or {}).get("probe") or [])]:
        rel = (h.get("with") or {}).get("contract")
        if rel and not (root / rel).exists():
            bad(f"phase {p['name']} hook {h.get('id')} names contract {rel}, "
                f"which does not exist")

# ── every phase has a documentation page, and every page a phase ──────────
# This replaces BE1's "every flows/phases folder has a phase declared here".
# The folders are gone (BE4), and the thing that can now drift out from under
# a reader is `docs/phases/`: a page for a phase nobody runs, or a phase
# nobody documented. `04-workers-restore` is deliberately covered by
# `04-workers.md`, and `03-infrastructure-database` by `03-infrastructure.md`
# — each pair of landings is one story, filed under one milestone.
DOC_SHARED = {"04-workers-restore": "04-workers", "03-infrastructure-database": "03-infrastructure"}
docs_dir = root / "docs" / "phases"
pages = {f.stem for f in docs_dir.glob("*.md")} - {"README", "TIMINGS"}
for p in phases:
    want = DOC_SHARED.get(p["name"], p["name"])
    if want not in pages:
        bad(f"phase {p['name']} has no page at docs/phases/{want}.md")
for page in sorted(pages):
    if page not in by_name and page not in DOC_SHARED.values():
        bad(f"docs/phases/{page}.md documents a phase repo-blueprint.yaml "
            f"does not declare")

# ── narration: authored here, printed from state (BE2) ────────────────────
#
# The plan put these checks in manifest.test.sh. They are here instead, and
# the reason is the same one that makes the checks worth having: that test is
# about `blueprint.yaml`, the CONSOLE manifest, and what it promises an
# operator. Narration is a property of `repo-blueprint.yaml`, so putting the
# checks there would have meant reading a second file in a test named after
# the first.
#
# What orun's event stream actually carries, which is what a line may name.
META_AT = {
    # start/await/failed render against the phase's opening meta …
    "start": {"files", "expectedMinutes"},
    "await": {"files", "expectedMinutes"},
    "failed": {"files", "expectedMinutes"},
    # … and only `done` has run to a close, so only `done` knows how long it
    # took or what comes next. A `start` line naming `elapsed` would render
    # empty at the one moment it was written for.
    "done": {"files", "expectedMinutes", "elapsed", "next"},
}
STATE_WORDS = {"done", "failed", "complete", "completed", "succeeded", "skipped"}
PHASE_KEYS = {"name", "title"}
input_keys = set((bp.get("inputs") or {}).keys())

# THE WORKSPACE COMES FROM THE BUILD. A console build cannot send
# `orunWorkspace` (the manifest's input keys are lowercase, and the console
# holds only repository facts), so without `from: workspace` it is empty
# there, and phase 01 writes `workspace: ws_SET_ME` into the product, points
# every secret ref at the repository's name, and links with `--org ""`.
# orun >= v2.58.11 fills it from the workspace the build runs in.
ws_input = (bp.get("inputs") or {}).get("orunWorkspace") or {}
if ws_input.get("from") != "workspace":
    bad("inputs.orunWorkspace must declare `from: workspace` — a console build has no other way to say it")

def strip_expressions(line):
    out, rest = [], line
    while True:
        i = rest.find("{{")
        if i < 0:
            out.append(rest)
            return "".join(out)
        out.append(rest[:i])
        j = rest.find("}}", i)
        if j < 0:
            return "".join(out)
        rest = rest[j + 2:]

def refs(line):
    """Every `.a.b` path inside an expression."""
    found = []
    for expr in re.findall(r"\{\{(.*?)\}\}", line, re.S):
        found += re.findall(r"\.([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*)", expr)
    return found

def check_line(where, line, slot, hook_ids):
    # Rule 2: prose may describe the world, never assert the run's state.
    prose = strip_expressions(line).lower()
    for w in STATE_WORDS:
        if re.search(rf"\b{w}\b", prose):
            bad(f"{where} asserts {w!r} — `state` is the truth and narration is "
                f"the caption. Describe the world, not the run.")
    # Rule 3: every reference resolves against what the engine actually emits.
    for ref in refs(line):
        parts = ref.split(".")
        root = parts[0]
        if root == "phase":
            if len(parts) != 2 or parts[1] not in PHASE_KEYS:
                bad(f"{where} names .{ref}; a phase carries {sorted(PHASE_KEYS)}")
        elif root == "inputs":
            if len(parts) != 2 or parts[1] not in input_keys:
                bad(f"{where} names .{ref}, which is not a declared input")
        elif root == "meta":
            allowed = META_AT.get(slot, META_AT["start"])
            if len(parts) != 2 or parts[1] not in allowed:
                bad(f"{where} names .{ref}; the {slot} event carries "
                    f"{sorted(allowed)}")
        elif root == "hooks":
            if len(parts) < 2 or parts[1] not in hook_ids:
                bad(f"{where} names .{ref}; this phase has no hook {parts[1] if len(parts)>1 else '?'!r}")
        else:
            bad(f"{where} names .{ref}; narration may reference phase, inputs, "
                f"meta and hooks")

for p in phases:
    n = p.get("narrate") or {}
    ids = {h.get("id") for h in hooks_of(p)}
    for slot in ("start", "await", "done", "failed"):
        line = n.get(slot)
        if not line:
            bad(f"phase {p['name']} declares no narrate.{slot} — an operator sees "
                f"a generated line instead of the one this baseline meant")
            continue
        check_line(f"phase {p['name']} narrate.{slot}", line, slot, ids)

    # An `await` is the one place an operator is left waiting with nothing
    # happening on screen, so it is the one place a line is not optional.
    for h in ((p.get("hooks") or {}).get("await") or []):
        line = h.get("narrate")
        if not line:
            bad(f"phase {p['name']} await hook {h.get('id')} declares no narrate "
                f"— a wait with no words reads as a stalled build")
            continue
        check_line(f"phase {p['name']} hook {h.get('id')} narrate", line, "done", ids)

    for slot in ("pre", "post"):
        for h in ((p.get("hooks") or {}).get(slot) or []):
            if h.get("narrate"):
                check_line(f"phase {p['name']} hook {h.get('id')} narrate",
                           h["narrate"], "start", ids)

# ── what BE1 and BE4 deleted stays deleted ────────────────────────────────
if (root / "flows").exists():
    bad("flows/ is back — the bootstrap is the blueprint, and every mechanism "
        "that layer carried is a typed action in the orun binary (BE4)")
if (root / "tooling" / "blueprint" / "split-phases.py").exists():
    bad("split-phases.py is back — orun's phase overlay refuses the cross-phase "
        "edge the splitter used to prune")

if problems:
    print("FAIL: the blueprint's phases and the bootstrap disagree:", file=sys.stderr)
    for p in problems:
        print(f"  - {p}", file=sys.stderr)
    sys.exit(1)

placed = sum(len(p.get("modules") or []) for p in phases)
narrated = sum(len(p.get("narrate") or {}) for p in phases)
narrated += sum(1 for p in phases for h in hooks_of(p) if h.get("narrate"))
print(f"   {len(phases)} phases, {placed} modules, "
      f"{len(HOOK_ONLY)} hook-only — in execution order")
print(f"   {narrated} authored narration lines, every reference resolving")
PY

echo "phases.test.sh: ok"
