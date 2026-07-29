#!/usr/bin/env bash
# One bootstrap batch: un-park the named components, PR the change, wait for
# checks, merge, then wait for the main convergence run that DEPLOYS the batch
# and require it green. Driven by flows/bootstrap-flow.yaml, usable by hand:
#
#   flows/batch.sh <batch-name> <component> [component…]
#
# Requires: gh authenticated for this repo; a clean tree on main.
set -euo pipefail

batch="${1:?usage: batch.sh <batch-name> <component>…}"
shift
[ "$#" -gt 0 ] || { echo "batch.sh: name at least one component" >&2; exit 2; }

git checkout main -q
git pull -q
git checkout -qb "bootstrap/${batch}"

node flows/common/park.mjs unpark "$@"

git add -A
git commit -qm "bootstrap(${batch}): enable ${*}

Un-parks this batch's environment subscriptions; the merge's main
convergence deploys exactly these components, in dependency order."
git push -qu origin "bootstrap/${batch}"

pr_url="$(gh pr create --title "bootstrap(${batch}): enable ${*}" \
  --body "Bootstrap batch \`${batch}\`: un-parks ${*}. Merging deploys this batch via the main convergence run." )"
echo "PR: ${pr_url}"

# Wait for PR checks (verify lanes for the newly-enabled components).
until state="$(gh pr checks "${pr_url}" --json bucket \
    --jq 'if length == 0 then "pending" elif all(.[].bucket; . != "pending") then "done" else "pending" end' 2>/dev/null)" \
    && [ "${state}" = "done" ]; do
  sleep 30
done
fails="$(gh pr checks "${pr_url}" --json bucket --jq '[.[]|select(.bucket=="fail")]|length')"
if [ "${fails}" != "0" ]; then
  echo "batch ${batch}: ${fails} check(s) failed on the PR — fix before merging" >&2
  gh pr checks "${pr_url}" --json name,bucket --jq '.[]|select(.bucket=="fail")|.name' >&2
  exit 1
fi

gh pr merge "${pr_url}" --squash --delete-branch
git checkout main -q
git pull -q

# The merge's main run is the DEPLOY — wait for it and require green.
sleep 30
run_id="$(gh run list --branch main --limit 1 --json databaseId --jq '.[0].databaseId')"
echo "convergence run: ${run_id}"
until st="$(gh run view "${run_id}" --json status --jq .status 2>/dev/null)" && [ "${st}" = "completed" ]; do
  sleep 40
done
conclusion="$(gh run view "${run_id}" --json conclusion --jq .conclusion)"
if [ "${conclusion}" != "success" ]; then
  echo "batch ${batch}: main convergence ${conclusion}" >&2
  gh run view "${run_id}" --json jobs --jq '.jobs[]|select(.conclusion=="failure")|.name' >&2
  exit 1
fi
echo "✓ batch ${batch} deployed and verified (run ${run_id})"
