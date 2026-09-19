#!/usr/bin/env bash
# TIER 1, THE OTHER HALF — the tree is placed, branded, and made to answer
# (saas-bootstrap-engine BE5b; ported from cirrus).
#
# BE5a could only gate the DERIVED placement: a whole-blueprint `orun new`
# refused before writing a byte, because every phase's `requires` was checked
# up front and `02-foundation` asked whether `01-scaffold` was on disk during
# the run about to write it. orun BE-O11 fixed that, and BE-O12 fixed what it
# then exposed — that a BRANDED predecessor reads `drifted`, which the gate was
# refusing, and which `--resume` was silently overwriting back to the baseline.
#
# So this file does what the design's Tier 1 asks and BE5a could not:
#
#   1. place the whole blueprint from tests/fixtures/acme.json, offline;
#   2. assert the gates orun runs INSIDE that placement actually ran — the
#      two-parser check on every generated component.yaml, and `orun validate`
#      + `orun plan --dry-run` in the produced tree. They come free with a
#      placement, which is exactly why they need asserting: a future orun that
#      stopped running them would weaken this tier in silence, and BE1a exists
#      because that already happened once with a version pin;
#   3. brand it as `01-scaffold`'s hook chain does, then `rebrand.mjs --verify`;
#   4. run the leak rules over the REAL FILES rather than the derivation;
#   5. check the API base the product ends up with against the rule
#      `blueprint.yaml` states as its `derive` — the last mile of BE3's gate,
#      in the product;
#   6. THE PHASED SEQUENCE THROUGH A REBRAND: place 01, brand, then place the
#      phases that follow. This is the step no test in this repository has ever
#      taken, and it is where BE-O12's two defects lived.
#
# Needs: orun (the pinned version) + node + python3 + git. No network, no
# credential. Nothing here contacts a provider: placement writes files, and
# since BE-O12 a run with hooks off does not probe.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"

command -v orun >/dev/null || { echo "placement.test.sh needs orun on PATH" >&2; exit 1; }
command -v node >/dev/null || { echo "placement.test.sh needs node for rebrand" >&2; exit 1; }

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
fails=0
fail() { echo "  ✕ $*" >&2; fails=$((fails + 1)); }

# The fixture is the source of inputs, so a new required input fails HERE rather
# than in front of an operator. `domain` is forced on: 07-domain is conditional,
# and a tier that never places a phase cannot vouch for it.
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

# orun's repo-scale gate discovers apps/infra/packages/tests, and a missing root
# is a hard failure. `discovery-roots` places the .gitkeep files but the gate
# runs against the directory, so they exist before the run — the same order
# 01-scaffold's workflow used.
tree="$scratch/product"
mkdir -p "$tree"/{apps,infra,packages,tests}
for d in apps infra packages tests; do touch "$tree/$d/.gitkeep"; done

echo "── placing the whole blueprint (offline, no credential)"
if ! orun new --blueprint "$root/repo-blueprint.yaml" --out "$tree" "${sets[@]}" \
     > "$scratch/place.log" 2>&1; then
  echo "FAIL: the placement did not run" >&2
  tail -20 "$scratch/place.log" >&2
  exit 1
fi

# ── the gates that ride inside the placement ───────────────────────────────
# `orun new` prints this line only after running validate + plan --dry-run in
# the produced tree. Its absence means the tier lost a check without failing.
grep -q "repo gate: validate + plan --dry-run passed" "$scratch/place.log" \
  || fail "the placement did not report the repo-scale gate — \`orun validate\`
     and \`orun plan --dry-run\` are Tier 1 checks that ride inside \`orun new\`,
     and a silent loss of them is exactly the regression BE1a was about"
placed_count="$(find "$tree" -type f -not -path "*/.orun/*" | wc -l | tr -d ' ')"
[ "$placed_count" -ge 500 ] || fail "only $placed_count files placed — that is not a product"

echo "   $placed_count files placed; the repo-scale gate ran"

# ── brand it, exactly as 01-scaffold's hooks do ────────────────────────────
echo "── branding, then rebrand --verify"
(
  cd "$tree"
  git init -q -b main
  git config user.email t@example.invalid
  git config user.name "tier one"
  printf 'baseline/\n.orun/\n' >> .gitignore
  git add -A
) >/dev/null 2>&1
if ! (cd "$tree" && node "$root/tooling/rebrand/rebrand.mjs" \
      --values .rebrand/values.json --allow-dirty) > "$scratch/brand.log" 2>&1; then
  echo "FAIL: rebrand did not complete" >&2
  tail -20 "$scratch/brand.log" >&2
  exit 1
fi
if ! (cd "$tree" && node "$root/tooling/rebrand/rebrand.mjs" \
      --values .rebrand/values.json --verify) > "$scratch/verify.log" 2>&1; then
  echo "FAIL: rebrand --verify found baseline identity left in the product" >&2
  tail -20 "$scratch/verify.log" >&2
  exit 1
fi
echo "   branded; no baseline-identity residue"

# ── the leak rules, over the files rather than the derivation ──────────────
echo "── what the product actually carries"
python3 - "$tree" "$root" <<'PY'
import pathlib, re, sys
tree, root = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
problems = []
def bad(m): problems.append(m)

placed = sorted(
    str(p.relative_to(tree))
    for p in tree.rglob("*")
    if p.is_file() and ".git" not in p.parts and ".orun" not in p.parts
)

# An exact set, not a prefix — the point of one module per file is that a new
# file in ai/context/ cannot ship without a module and a diff.
ALLOWED_AI = {"ai/context/deployment.md", "ai/context/operations.md"}
shipped_ai = {p for p in placed if p.startswith("ai/")}
for extra in sorted(shipped_ai - ALLOWED_AI):
    bad(f"{extra} shipped and is this repository's own state")
for missing in sorted(ALLOWED_AI - shipped_ai):
    bad(f"{missing} is declared a product file and did not ship")

NEVER = ("flows/", "agents/", "tasks/", "specs/", "testing/", "hooks/",
         "docs/phases/", "tooling/rebrand/", "tooling/bootstrap/",
         "tooling/fork/", "tooling/migrations/",
         "FORKING.md", "BOOTSTRAP.md", "repo-blueprint.yaml", "blueprint.yaml")
for p in placed:
    for never in NEVER:
        if p == never or p.startswith(never):
            bad(f"{p} shipped — it is the factory, not the product")

# PROVENANCE, over the BRANDED tree. Deliberately not a search for "lumen":
# rebrand rewrites this repository's name into the product's, so flagging it
# would fail on input rebrand has already fixed. What rebrand has no rule for
# is a sentence about where the baseline came from — and unlike the leak gate,
# which can only read this repository's copy of the two files, this reads what
# the product ended up with, after every rewrite. After branding, "lumen" is
# ALSO a leftover here — rebrand --verify above owns that verdict.
PROVENANCE = re.compile(
    r"\bfork(ed)? (of|from)\b|\bbaseline (repo|repository|commit)\b", re.I)
for rel in sorted(shipped_ai & ALLOWED_AI):
    for n, line in enumerate((tree / rel).read_text(errors="replace").splitlines(), 1):
        if PROVENANCE.search(line):
            bad(f"{rel}:{n} tells the product where the BASELINE came from: "
                f"{line.strip()[:70]}")

if problems:
    print("FAIL: the product carries the baseline:", file=sys.stderr)
    for p in problems:
        print(f"  - {p}", file=sys.stderr)
    sys.exit(1)
print(f"   {len(placed)} product files; ai/context is exactly "
      f"{len(ALLOWED_AI)}; no factory, no provenance prose")
PY

# ── the derived API base, in the product ───────────────────────────────────
# BE3 states `derive: "https://api.{productdomain}"` in blueprint.yaml and holds
# it equal to rebrand.mjs's fallback. Both of those are checks on the RULES.
# This checks the value a product ends up with.
echo "── the API base the product ends up with"
python3 - "$tree" "$root" <<'PY'
import json, pathlib, re, sys
import yaml
tree, root = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
man = yaml.safe_load((root / "blueprint.yaml").read_text())["spec"]
derive = next((f.get("derive") for f in man["inputs"] if f["key"] == "apibaseurl"), None)
if not derive:
    sys.exit("blueprint.yaml no longer derives apibaseurl — this check has gone blind")
vals = json.loads((root / "tests/fixtures/acme.json").read_text())
want = re.sub(r"\{([a-z]+)\}",
              lambda m: {"productdomain": vals["productdomain"]}[m.group(1)], derive)
brand = (tree / "packages/cli/src/brand.ts").read_text()
m = re.search(r'DEFAULT_API_URL = "([^"]+)"', brand)
if not m:
    sys.exit("packages/cli/src/brand.ts no longer declares DEFAULT_API_URL — gone blind")
if m.group(1) != want:
    sys.exit(f"FAIL: the product's DEFAULT_API_URL is {m.group(1)!r}; "
             f"blueprint.yaml's derive over this fixture says {want!r}")
print(f"   DEFAULT_API_URL is {want} — the rule blueprint.yaml declares")
PY

# ── THE PHASED SEQUENCE THROUGH A REBRAND ──────────────────────────────────
# A fresh tree, phase by phase, with the branding in the middle where the real
# bootstrap puts it. Before orun BE-O12 this died at the second phase:
#
#     ✕ phase "02-foundation" requires 01-scaffold (drifted)
#
echo "── the phased sequence, with the rebrand where 01-scaffold puts it"
seq="$scratch/seq"
mkdir -p "$seq"/{apps,infra,packages,tests}
for d in apps infra packages tests; do touch "$seq/$d/.gitkeep"; done
orun new --blueprint "$root/repo-blueprint.yaml" --out "$seq" --phase 01-scaffold \
  "${sets[@]}" > "$scratch/p01.log" 2>&1 || {
    echo "FAIL: 01-scaffold did not place" >&2; tail -10 "$scratch/p01.log" >&2; exit 1; }
(
  cd "$seq"
  git init -q -b main
  git config user.email t@example.invalid
  git config user.name "tier one"
  printf 'baseline/\n.orun/\n' >> .gitignore
  git add -A
  node "$root/tooling/rebrand/rebrand.mjs" --values .rebrand/values.json --allow-dirty
) > "$scratch/seqbrand.log" 2>&1 || {
    echo "FAIL: the sequence's rebrand did not complete" >&2
    tail -10 "$scratch/seqbrand.log" >&2; exit 1; }

name_after_brand="$(python3 -c "import json;print(json.load(open('$seq/package.json'))['name'])")"
[ "$name_after_brand" = "acme-cloud" ] \
  || fail "after branding, package.json name is $name_after_brand, not the product's"

for ph in 02-foundation 03-infrastructure 03-infrastructure-database 04-workers 05-edge 06-console 07-domain; do
  if ! orun new --blueprint "$root/repo-blueprint.yaml" --out "$seq" --phase "$ph" \
       "${sets[@]}" > "$scratch/p-$ph.log" 2>&1; then
    fail "phase $ph refused after the rebrand: $(tail -1 "$scratch/p-$ph.log")"
  fi
done

# ── and a resume must not undo the branding ────────────────────────────────
# This is the destructive half of BE-O12. A resume over a branded product used
# to re-place every drifted phase, which is all of them, reverting the product's
# identity to the baseline's.
orun new --blueprint "$root/repo-blueprint.yaml" --out "$seq" --resume "${sets[@]}" \
  > "$scratch/resume.log" 2>&1 || {
    echo "FAIL: --resume did not run" >&2; tail -10 "$scratch/resume.log" >&2; exit 1; }
name_after_resume="$(python3 -c "import json;print(json.load(open('$seq/package.json'))['name'])")"
[ "$name_after_resume" = "acme-cloud" ] \
  || fail "--resume reverted the product's identity: package.json name is now
     $name_after_resume. A resume between phases must not un-brand a product."

[ "$fails" -eq 0 ] && \
  echo "   01 → 07 place through the rebrand; --resume leaves the branding alone"

[ "$fails" -eq 0 ] || { echo "placement.test.sh: $fails failure(s)" >&2; exit 1; }
echo "placement.test.sh: ok"
