#!/usr/bin/env bash
# Apply ONE blueprint phase into the product repo and rebrand the result.
# Identity comes from the repo's own .rebrand/values.json (written by the
# scaffold phase), so later phases need no identity inputs. Idempotent:
# writeTree is additive, rebrand is a no-op on already-branded files, and the
# phase provenance lock is archived like run-phases.sh does.
#
#   flows/common/apply-blueprint.sh <baseline-dir> <blueprint-file> <out> <workspace> [dryrun]
#
# dryrun "true": apply + rebrand in the working tree, show what changed, then
# revert everything (requires a clean tree, which is enforced regardless).
set -euo pipefail

baseline="${1:?baseline dir}"
bp="${2:?blueprint file (relative to baseline)}"
out="${3:?product repo dir}"
ws="${4:?workspace id or slug}"
dry="${5:-false}"

vals="$out/.rebrand/values.json"
[ -f "$vals" ] || { echo "apply-blueprint: no $vals — run the scaffold phase (flows/phases/01-scaffold) first" >&2; exit 1; }
getv() { python3 -c "import json;print(json.load(open('$vals')).get('$1') or '')"; }

sets=(
  --set "repoName=$(getv repoName)"
  --set "productName=$(getv productName)"
  --set "productDomain=$(getv productDomain)"
  --set "workersDevSubdomain=$(getv workersDevSubdomain)"
  --set "orunWorkspace=$ws"
)
for k in pascalName brandSlug cliBin apiBaseUrl salesEmail; do
  v="$(getv "$k")"
  [ -n "$v" ] && sets+=( --set "$k=$v" )
done

cd "$out"
if [ -n "$(git status --porcelain)" ]; then
  echo "apply-blueprint: $out working tree is not clean — commit/stash first" >&2
  exit 1
fi

orun new --blueprint "$baseline/$bp" --out "$out" "${sets[@]}"
if [ -f .orun/provenance.lock ]; then
  cp .orun/provenance.lock ".orun/provenance.$(basename "$bp" .yaml).lock"
fi

# Rebrand the freshly written files (tracked via the index so the sweep sees
# them); idempotent over the rest of the tree.
git add -A
node tooling/rebrand/rebrand.mjs --values "$vals" --allow-dirty
git add -A

if [ "$dry" = "true" ]; then
  echo "DRY RUN: this phase would land the following (then reverted locally):"
  git status --short | head -40
  n="$(git status --porcelain | wc -l | xargs)"
  echo "DRY RUN: $n path(s) total — reverting"
  git reset -q
  git checkout -q -- . 2>/dev/null || true
  git clean -qfd
  exit 0
fi

echo "apply-blueprint: $(git status --porcelain | wc -l | xargs) path(s) staged from $bp"
