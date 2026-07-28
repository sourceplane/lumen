#!/usr/bin/env bash
# One-time migration of LIVE terraform state: S3 (AWS) → the orun platform
# state backend (SB1). Run BEFORE merging the de-AWS flip — after the flip,
# applies read the http backend, and an empty one would plan to re-create
# resources that already exist.
#
# Requirements:
#   - AWS credentials able to read the sourceplane state buckets (the old
#     <env>-github-sourceplane-lumen-plan role's power, or an admin profile)
#   - orun logged in (orun auth login) as a workspace member
#   - terraform >= 1.15
#
# What it does, per component × environment:
#   1. init against the OLD S3 backend (workspace env:<env>) and `state pull`
#   2. `state rm` every aws_secretsmanager_* resource + data source — the
#      flipped config no longer declares them, and their prevent_destroy
#      guards would otherwise ERROR every future plan. The SM secrets remain
#      in AWS untouched (delete them manually after the 30d recovery window).
#   3. init against the PLATFORM http backend (TF_HTTP_* below) + `state push`
#
#   tooling/migrations/tfstate-to-orun.sh <org_public_id> <prj_public_id> <orun-access-token>
#
# The token is only used as the terraform http backend password; prefer a
# short-lived one (it is NOT stored). Get the ids from the console URL or
# `orun cloud status`.
set -euo pipefail

org="${1:?org public id (org_…)}"
prj="${2:?project public id (prj_…)}"
token="${3:?orun access token (backend password)}"
backend="${ORUN_BACKEND_URL:-https://api-edge-prod.oruncloud.workers.dev}"

COMPONENTS=(supabase cloudflare-kv cloudflare-hyperdrive cloudflare-domain)
ENVS=(stage prod)

repo_root="$(git rev-parse --show-toplevel)"

for comp in "${COMPONENTS[@]}"; do
  dir="$repo_root/infra/terraform/$comp/terraform"
  [ -d "$dir" ] || { echo "skip $comp (no terraform dir)"; continue; }
  for env in "${ENVS[@]}"; do
    echo "══ $comp/$env"
    work="$(mktemp -d)"
    state="$work/terraform.tfstate"

    # 1. Pull from the OLD S3 backend. Uses a scratch copy of the module with
    #    the s3 backend restored, so the working tree stays flipped.
    scratch="$work/module"
    cp -R "$dir" "$scratch"
    python3 - "$scratch/main.tf" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p).read()
s = s.replace('backend "http" {}', 'backend "s3" {\n    encrypt              = true\n    use_lockfile         = true\n    workspace_key_prefix = "env"\n  }')
open(p, "w").write(s)
PYEOF
    terraform -chdir="$scratch" init -input=false -reconfigure \
      -backend-config="bucket=sourceplane-$env" \
      -backend-config="key=lumen/$comp/terraform.tfstate" \
      -backend-config="region=${AWS_REGION:-us-east-1}" >/dev/null
    TF_WORKSPACE="$env" terraform -chdir="$scratch" state pull > "$state"
    [ -s "$state" ] || { echo "  no state for $comp/$env — skipping"; rm -rf "$work"; continue; }

    # 2. Drop the Secrets Manager resources from the pulled state.
    sm_addrs=$(TF_WORKSPACE="$env" terraform -chdir="$scratch" state list -state="$state" 2>/dev/null \
      | grep -E '^(data\.)?aws_secretsmanager' || true)
    if [ -n "$sm_addrs" ]; then
      # shellcheck disable=SC2086
      TF_WORKSPACE="$env" terraform -chdir="$scratch" state rm -state="$state" $sm_addrs
    fi

    # 3. Push into the platform backend (the flipped module, real dir).
    addr="$backend/v1/organizations/$org/projects/$prj/state/tfstate/$comp/$env"
    TF_HTTP_ADDRESS="$addr" TF_HTTP_LOCK_ADDRESS="$addr" TF_HTTP_UNLOCK_ADDRESS="$addr" \
    TF_HTTP_LOCK_METHOD=LOCK TF_HTTP_UNLOCK_METHOD=UNLOCK \
    TF_HTTP_USERNAME=orun TF_HTTP_PASSWORD="$token" \
      terraform -chdir="$dir" init -input=false -reconfigure >/dev/null
    TF_HTTP_ADDRESS="$addr" TF_HTTP_LOCK_ADDRESS="$addr" TF_HTTP_UNLOCK_ADDRESS="$addr" \
    TF_HTTP_LOCK_METHOD=LOCK TF_HTTP_UNLOCK_METHOD=UNLOCK \
    TF_HTTP_USERNAME=orun TF_HTTP_PASSWORD="$token" \
      terraform -chdir="$dir" state push "$state"
    echo "  ✓ migrated $comp/$env"
    rm -rf "$work"
  done
done

echo "state migration complete — verify with a plan-only CI run, then merge the flip."
