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

# (after the clean check: this may WRITE .rebrand/values.json, and the change
# then lands with this phase's PR)
# The workspace SLUG is what `secret://<workspace>/…` refs must carry (a ws_…
# id is not accepted there). Resolve it once from the platform and record it,
# so every phase's rebrand renames the workspace segment correctly — and so a
# product scaffolded before this existed self-heals on its next phase.
if [ -z "$(getv orunWorkspaceSlug)" ]; then
  slug="$ws"
  case "$ws" in
    ws_*|WS_*)
      slug="$( (cd "$out" && orun cloud check --org "$ws" 2>/dev/null) \
        | sed -n 's/.*allow-listed for org \([A-Za-z0-9_-]*\).*/\1/p' | head -1)"
      ;;
  esac
  if [ -n "$slug" ] && [ "$slug" != "$ws" -o "${ws#ws_}" = "$ws" ]; then
    python3 - "$vals" "$slug" <<'PY'
import json, sys
p, slug = sys.argv[1], sys.argv[2]
d = json.load(open(p))
d["orunWorkspaceSlug"] = slug
json.dump(d, open(p, "w"), indent=2)
open(p, "a").write("\n")
PY
    echo "apply-blueprint: workspace slug for secret refs = $slug"
  else
    echo "apply-blueprint: could not resolve the workspace SLUG for $ws — secret:// refs would name the wrong workspace. Pass a slug as --set workspace=<slug>, or set orunWorkspaceSlug in .rebrand/values.json." >&2
    exit 1
  fi
fi


orun new --blueprint "$baseline/$bp" --out "$out" "${sets[@]}"
if [ -f .orun/provenance.lock ]; then
  cp .orun/provenance.lock ".orun/provenance.$(basename "$bp" .yaml).lock"
fi

# Rebrand the freshly written files (tracked via the index so the sweep sees
# them); idempotent over the rest of the tree.
git add -A
# Run the BASELINE's rebrand (the pinned commit's tool), never the product's
# own copy — that copy is frozen at scaffold time and misses later fixes
# (hit live: a stale product rebrand re-broke the secret-ref workspace
# segment that the pinned baseline had already fixed).
node "$baseline/tooling/rebrand/rebrand.mjs" --values "$vals" --allow-dirty
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
