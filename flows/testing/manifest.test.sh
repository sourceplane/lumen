#!/usr/bin/env bash
# The manifest must state what the flows DO (saas-bootstrap-console BC2).
#
# `blueprint.yaml` is the contract the platform's bootstrap door reads and the
# console renders screen for screen. A manifest that drifts from the flows is a
# console that lies — it would show an operator a set of secrets that will not
# be created, or a programme that will not be laid out, with nothing failing
# until a customer's build was already running.
#
# Every check below compares the manifest to THE SCRIPT THAT DOES THE WORK,
# never to another copy of the same claim. That distinction is the whole design:
# `spec.source.tag` sat at `baseline-v1` against a live `baseline-v4` for three
# releases, past four contract tests in this very directory, because nothing
# compared it to anything that moved. A drift test between two files catches
# nothing.
#
# bash + python3 + git. No network, no fakes, no credential.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"

echo "── blueprint.yaml against the flows that realize it"
python3 - "$root" <<'PY'
import pathlib, re, sys

try:
    import yaml
except ImportError:
    sys.exit("PyYAML is required for the manifest contract test (pip install pyyaml)")

root = pathlib.Path(sys.argv[1])
problems = []

def bad(msg):
    problems.append(msg)

manifest_path = root / "blueprint.yaml"
if not manifest_path.exists():
    sys.exit("blueprint.yaml is missing from the repo root")
spec = (yaml.safe_load(manifest_path.read_text()) or {}).get("spec") or {}

# ── 1. the field that cannot be true ──────────────────────────────────────
# A file fetched AT a tag cannot also name one. Its only possible states are
# "agrees with the registry" and "rotting", and it spent three releases in the
# second. If it comes back, this test is the thing that says so.
if "tag" in (spec.get("source") or {}):
    bad("spec.source.tag is back. The registry pins the tag; this file is fetched at it.")

# ── 2. required blocks ────────────────────────────────────────────────────
for key in ("source", "overview", "requires", "inputs", "secrets", "programme", "bootstrap", "verify"):
    if key not in spec:
        bad(f"spec.{key} is missing — the console renders it")

# ── 3. inputs: askedBy is the console/agent division of labour ────────────
for i, field in enumerate(spec.get("inputs") or []):
    key = field.get("key", f"#{i}")
    asked = field.get("askedBy")
    if asked not in ("console", "agent"):
        bad(f"inputs[{key}].askedBy is {asked!r} — must be 'console' or 'agent'")
    # A console input gates the flow, so the console must be able to validate
    # it before offering Continue. Without a pattern it can only accept
    # anything, which makes the gate decorative.
    if asked == "console" and not field.get("pattern"):
        bad(f"inputs[{key}] is asked by the console but declares no pattern")

# ── 4. secrets vs create-secrets.sh ───────────────────────────────────────
# The script's `create <KEY> <provider> <conn> <template>` calls are the truth.
script = (root / "flows/common/create-secrets.sh").read_text()
actual = {
    m.group(1): (m.group(2), m.group(3))
    for m in re.finditer(r"^create\s+([A-Z][A-Z0-9_]*)\s+(\S+)\s+\S+\s+(\S+)\s*$", script, re.M)
}
if not actual:
    bad("found no `create <KEY> <provider> <conn> <template>` calls in create-secrets.sh — "
        "the script's shape changed and this check has gone blind")

declared = {s.get("key"): (s.get("provider"), s.get("template")) for s in (spec.get("secrets") or [])}
for key in sorted(set(actual) - set(declared)):
    bad(f"create-secrets.sh creates {key} and the manifest does not declare it")
for key in sorted(set(declared) - set(actual)):
    bad(f"the manifest declares secret {key} and create-secrets.sh never creates it")
for key in sorted(set(actual) & set(declared)):
    if actual[key] != declared[key]:
        bad(f"{key}: manifest says provider/template {declared[key]}, the script uses {actual[key]}")

# ── 5. programme vs the umbrella's ensure-milestone calls ─────────────────
umbrella = (root / "flows/phases/00-all/workflow.yaml").read_text()
loop = re.search(r"for phase in ([0-9a-z\- ]+); do", umbrella)
if not loop:
    bad("could not find the umbrella's `for phase in …` milestone loop — this check has gone blind")
    looped = []
else:
    looped = loop.group(1).split()
# Milestones ensured outside the loop, each on its own line.
extra = re.findall(r'ensure-milestone "\$epic" ([0-9][0-9a-z\-]+)', umbrella)
conditional = set(re.findall(r'!= "true" \]\s*\|\|.*?ensure-milestone "\$epic" ([0-9][0-9a-z\-]+)', umbrella))
ensured = looped + extra

prog = spec.get("programme") or {}
ms = prog.get("milestones") or []
if any(not isinstance(m, dict) or "name" not in m for m in ms):
    bad("every programme.milestones entry must be a mapping with a `name` "
        "(so a conditional one can carry its `when`)")
    names, declared_cond = [], set()
else:
    names = [m["name"] for m in ms]
    declared_cond = {m["name"] for m in ms if m.get("when")}

if names != ensured:
    bad(f"programme.milestones {names} != the umbrella's {ensured}")
if declared_cond != conditional:
    bad(f"conditional milestones disagree: manifest says {sorted(declared_cond) or '[]'}, "
        f"the umbrella guards {sorted(conditional) or '[]'}")

# The epic slug must match the umbrella's own default, or the console previews
# an epic under a slug the build will not use.
slug = re.search(r'epicslug:\s*\n\s*type: string\s*\n\s*default: "([^"]+)"', umbrella)
if slug and prog.get("epicSlug") != slug.group(1):
    bad(f"programme.epicSlug {prog.get('epicSlug')!r} != the umbrella's default {slug.group(1)!r}")

# ── 6. every declared path exists at this commit ──────────────────────────
boot = spec.get("bootstrap") or {}
for field in ("umbrella", "agentBrief"):
    rel = boot.get(field)
    if not rel:
        bad(f"bootstrap.{field} is missing")
    elif not (root / rel).exists():
        bad(f"bootstrap.{field} names {rel}, which does not exist")

# ── 7. verify URLs may only interpolate inputs that exist ─────────────────
input_keys = {f.get("key") for f in (spec.get("inputs") or [])} | {"env"}
for url in ((spec.get("verify") or {}).get("urls") or []):
    for ph in re.findall(r"\{([a-zA-Z0-9_]+)\}", url):
        if ph not in input_keys:
            bad(f"verify url interpolates {{{ph}}}, which is not an input")

if problems:
    print("FAIL: the manifest and the flows disagree:", file=sys.stderr)
    for p in problems:
        print(f"  - {p}", file=sys.stderr)
    sys.exit(1)

print(f"   {len(declared)} secret(s) and {len(names)} milestone(s) agree with the flows that create them")
PY

echo "manifest.test.sh: ok"
