#!/usr/bin/env bash
# Instantiate the Lumen baseline one phase at a time.
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
#   blueprints/run-phases.sh <out-dir> [--set k=v ...]
#
# Example:
#   blueprints/run-phases.sh ~/sourceplane/acme-cloud \
#     --set repoName=acme-cloud \
#     --set productName="Acme Cloud" \
#     --set productDomain=acme.dev \
#     --set orunWorkspace=ws_ACME1234
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
out="${1:?usage: run-phases.sh <out-dir> [--set k=v ...]}"
shift

# Portable array fill — macOS ships bash 3.2, which has no `mapfile`.
phases=()
for f in "$here"/[0-9][0-9]-*.yaml; do
  [ -e "$f" ] || continue
  phases+=("$f")
done
[ "${#phases[@]}" -gt 0 ] || { echo "no phase blueprints in $here" >&2; exit 1; }

for i in "${!phases[@]}"; do
  bp="${phases[$i]}"
  stem="$(basename "$bp" .yaml)"
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
