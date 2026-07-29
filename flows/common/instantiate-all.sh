#!/usr/bin/env bash
# EXPRESS instantiation: apply every phase blueprint into one --out, in one
# go, producing the FULL product tree. This is the scaffolding half of the
# express path (flows/bootstrap-flow.yaml deploys what this creates).
#
# The paced alternative is flows/phases/ — seven workflows that each apply
# ONE slice and deploy it (see flows/phases/README.md). Same blueprints,
# different pacing: this script applies them all before anything deploys.
#
# Each phase is its own Blueprint (see split-phases.py). They accumulate into a
# single --out because orun's writeTree is additive (MkdirAll + WriteFile per
# path, no wipe), and the phases write disjoint paths.
#
# Two things this wrapper exists to handle:
#
#  1. PROVENANCE IS LAST-WRITE-WINS. Every `orun new` rewrites
#     .orun/provenance.lock, so a naive loop leaves you with only the final
#     phase's provenance (17 of 65 modules). Each phase's lock is archived to
#     .orun/provenance.<NN>-<phase>.lock before the next run clobbers it.
#
#  2. HOOKS NEED THE COMPLETE TREE. rebrand.mjs enumerates with `git ls-files`,
#     so --run-hooks is passed only on the final phase — which is also the only
#     phase carrying a hooks: block.
#
# Usage:
#   flows/common/instantiate-all.sh <out-dir> [--set k=v ...]
#
# Example:
#   flows/common/instantiate-all.sh ~/sourceplane/acme-cloud \
#     --set repoName=acme-cloud \
#     --set productName="Acme Cloud" \
#     --set productDomain=acme.dev \
#     --set orunWorkspace=ws_ACME1234
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/../.." && pwd)"
out="${1:?usage: instantiate-all.sh <out-dir> [--set k=v ...]}"
shift

# The phase blueprints live IN their phase folders (flows/phases/<n>/
# blueprint.yaml — co-located with each phase's workflow and README). For
# the express full-tree instantiation they are applied in BLUEPRINT
# dependency order — content phases first, the workspace/root scaffold
# LAST, because it is the phase that carries hooks and hooks need the
# complete tree. (The phased path runs the scaffold FIRST instead and
# replicates the hooks inline — see flows/phases/README.md.)
phases=()
for d in 02-foundation 03-infrastructure 04-workers 05-edge 06-console 07-domain 01-scaffold; do
  f="$root/flows/phases/$d/blueprint.yaml"
  [ -e "$f" ] || { echo "missing phase blueprint: $f" >&2; exit 1; }
  phases+=("$f")
done

for i in "${!phases[@]}"; do
  bp="${phases[$i]}"
  stem="$(basename "$(dirname "$bp")")"
  last=$(( i == ${#phases[@]} - 1 ))

  hooks=()
  # Only the final phase declares hooks, and they need the whole tree.
  [ "$last" -eq 1 ] && hooks=(--run-hooks)

  echo "── phase $((i + 1))/${#phases[@]}: $stem"
  # ${arr[@]+"${arr[@]}"} — bash 3.2 (macOS) treats an empty array as unset
  # under `set -u`, so the plain "${hooks[@]}" form aborts on every phase but
  # the last.
  orun new --blueprint "$bp" --out "$out" "$@" ${hooks[@]+"${hooks[@]}"}

  # Archive before the next phase overwrites it.
  if [ -f "$out/.orun/provenance.lock" ]; then
    cp "$out/.orun/provenance.lock" "$out/.orun/provenance.$stem.lock"
  fi
done

echo
echo "✓ ${#phases[@]} phases → $out"
echo "  per-phase provenance: $out/.orun/provenance.*.lock"
