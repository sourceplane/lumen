#!/usr/bin/env bash
# THE LEAK GATE — what a product carries, and what stays in the factory
# (saas-bootstrap-engine BE5, Tier 1; ported from cirrus).
#
# `BOOTSTRAP.md` describes a product as the thing lumen makes, not a copy of
# lumen. Until now the `ai-context` module copied the whole of `ai/context/`,
# so every product shipped this repository's planning state — `current.md`,
# `decisions.md`, `open-risks.md` — which after rebrand read as statements
# about the CUSTOMER's product, in the file an agent is pointed at first. And
# the `flows`, `agents` and `tooling` modules shipped the factory itself.
#
# WHAT THIS ASKS, AND WHAT IT CANNOT YET. It asks orun to DERIVE the placement
# — every file every phase would write — and gates that set. Derivation runs no
# hooks, contacts nothing and writes nothing.
#
# It does NOT place the tree and brand it; `testing/placement.test.sh` does.
#
# Needs: orun (the pinned version) + python3. No network, no credential.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"

command -v orun >/dev/null || { echo "leak.test.sh needs orun on PATH" >&2; exit 1; }

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

echo "── deriving what every phase would place"
# Inputs come from the fixture, so a new required input fails HERE rather than
# in front of an operator. `domain` is forced on: 07-domain is conditional, and
# a gate that never looks at a phase cannot vouch for it.
sets=()
while IFS=$'\t' read -r k v; do sets+=( --set "$k=$v" ); done < <(
  python3 - "$root/tests/fixtures/acme.json" <<'PY'
import json, sys
vals = json.load(open(sys.argv[1]))
vals["domain"] = True
for k, v in vals.items():
    if k.startswith("_"):
        continue
    print(f"{k}\t{'true' if v is True else 'false' if v is False else v}")
PY
)
orun new --blueprint "$root/repo-blueprint.yaml" --status --json \
  --out "$scratch/empty" "${sets[@]}" > "$scratch/status.json"

python3 - "$scratch/status.json" "$root" <<'PY'
import json, pathlib, sys

status = json.load(open(sys.argv[1]))
root = pathlib.Path(sys.argv[2])
problems = []
def bad(m): problems.append(m)

# Against an empty output directory every file a phase places is "missing", so
# the union of those lists IS the product's file set.
placed = sorted({f for ph in status["phases"] for f in (ph.get("missing") or [])})
if len(placed) < 500:
    sys.exit(f"only {len(placed)} files derived — the tree is not a product")

# ── the product's context pack, exactly ─────────────────────────────────────
# An exact set, not a prefix. That is the whole point of one module per file:
# a new file in ai/context/ cannot ship without somebody writing a module for
# it and saying so in a diff.
ALLOWED_AI = {"ai/context/deployment.md", "ai/context/operations.md"}
shipped_ai = {p for p in placed if p.startswith("ai/")}
for extra in sorted(shipped_ai - ALLOWED_AI):
    bad(f"{extra} ships to the product and is this repository's own state")
for missing in sorted(ALLOWED_AI - shipped_ai):
    bad(f"{missing} is declared a product file and would not ship")

# ── the factory never ships ────────────────────────────────────────────────
NEVER = ("flows/", "agents/", "tasks/", "specs/", "testing/", "hooks/",
         "docs/phases/", "tooling/rebrand/", "tooling/bootstrap/",
         "tooling/fork/", "tooling/migrations/",
         "FORKING.md", "BOOTSTRAP.md", "repo-blueprint.yaml", "blueprint.yaml")
for p in placed:
    for never in NEVER:
        if p == never or p.startswith(never):
            bad(f"{p} would ship — it is the factory, not the product")

# ── and by content: PROVENANCE, which rebrand has no rule for ──────────────
# Deliberately NOT a search for "lumen". rebrand.mjs rewrites this
# repository's own name into the product's — that is its whole job — so
# flagging it here would mean failing on input rebrand is about to fix, and
# testing rebrand's work in the wrong place against the wrong tree.
#
# What rebrand cannot fix is a sentence about where the product CAME FROM.
# Cirrus shipped "Provenance — Cirrus from the Lumen baseline": rebrand turns
# the first name into the product's and leaves the rest standing, so the
# customer is told their product was forked from something they have never
# seen. This catches that prose appearing inside a file that ships.
import re
PROVENANCE = re.compile(
    r"\bfork(ed)? (of|from)\b|\bbaseline (repo|repository|commit)\b",
    re.I,
)
for rel in sorted(shipped_ai & ALLOWED_AI):
    src = root / rel
    if not src.exists():
        bad(f"{rel} is declared a product file and is not in this repository")
        continue
    for n, line in enumerate(src.read_text(errors="replace").splitlines(), 1):
        if PROVENANCE.search(line):
            bad(f"{rel}:{n} tells the product where the BASELINE came from, "
                f"which rebrand cannot rewrite: {line.strip()[:70]}")

if problems:
    print("FAIL: the product would carry the baseline:", file=sys.stderr)
    for p in problems:
        print(f"  - {p}", file=sys.stderr)
    sys.exit(1)

print(f"   {len(placed)} files derived across every phase")
print(f"   ai/context is exactly {len(ALLOWED_AI)} declared file(s)")
print(f"   none of the {len(NEVER)} factory paths; "
      f"no baseline provenance in the context pack")
PY

echo "leak.test.sh: ok"
