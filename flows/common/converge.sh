#!/usr/bin/env bash
# Wait for a main convergence run and require it green — RESUMING it through
# transient failures instead of giving up. The CI is resume-capable (exec-id =
# run id, `orun run --retry`): `gh run rerun --failed` re-opens exactly the
# failed lanes of the SAME orun execution, memoized jobs stay done, and
# dependents wait for their upstreams' retry claims. So a convergence that
# trips on something transient (propagation, a rate-limited resolve, a runner
# eviction) heals in place — a real regression still fails every resume and
# surfaces after the budget.
#
#   flows/common/converge.sh [run-id] [max-resumes]
#
# With no run-id, waits for the newest run on main. Requires: gh authenticated.
set -euo pipefail

run_id="${1:-}"
max_resumes="${2:-3}"

if [ -z "${run_id}" ]; then
  # The caller just pushed; give GitHub a beat to materialize the run.
  sleep 20
  run_id="$(gh run list --branch main --limit 1 --json databaseId --jq '.[0].databaseId')"
fi
echo "convergence run: ${run_id} (resume budget: ${max_resumes})"

attempt=0
while :; do
  until st="$(gh run view "${run_id}" --json status --jq .status 2>/dev/null)" \
      && [ "${st}" = "completed" ]; do
    sleep 40
  done
  conclusion="$(gh run view "${run_id}" --json conclusion --jq .conclusion)"
  if [ "${conclusion}" = "success" ]; then
    echo "✓ convergence green (run ${run_id}, resumes used: ${attempt})"
    exit 0
  fi
  if [ "${attempt}" -ge "${max_resumes}" ]; then
    echo "✕ convergence ${conclusion} after ${attempt} resume(s) (run ${run_id}); failed lanes:" >&2
    gh run view "${run_id}" --json jobs --jq '.jobs[]|select(.conclusion=="failure")|.name' >&2
    exit 1
  fi
  attempt=$((attempt + 1))
  echo "↻ convergence ${conclusion} — resuming failed lanes (${attempt}/${max_resumes})"
  gh run rerun "${run_id}" --failed
  sleep 30
done
