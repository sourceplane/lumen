#!/usr/bin/env bash
# The sandbox agent's ONE command (saas-baseline-tracking, agent brief v2).
#
# The agent asks three questions and runs this. Everything else the old brief
# asked the agent to do — find the checkout, export a GitHub token, install
# gh, set a git identity, pick the CI watch mode, lay out the programme, run
# the umbrella, attach the deployment record, compose the summary — happens
# HERE, from the environment the platform prepared, and is reported back in
# four kinds of line the agent copies rather than composes:
#
#   UPDATE: …           a phase finished (or the build started)
#   ACTION REQUIRED: …  something only the operator can do; wait, then re-run
#   FAILED: …           the build stopped; the lines above say why
#   DONE                followed by the summary block
#
# Three live bootstraps showed why: told about the token endpoint, the agent
# read the token file and printed it; told "install gh if missing", it
# installed an npm package of the same name; told to pick watch=true/false,
# it reasoned about GitHub App grants. None of that is the agent's job.
#
# Runs from anywhere inside the sandbox; the wrapper workflow
# (flows/agent/workflow.yaml) is how the platform-delivered brief invokes it.
set -euo pipefail

usage() {
  echo "usage: build.sh --product-name <name> --product-domain <domain> --subdomain <workers.dev subdomain> [--watch auto|true|false] [--domain true|false]" >&2
  exit 2
}
name="" pdomain="" sub="" watch="${BUILD_WATCH:-auto}" zone="${BUILD_DOMAIN:-false}"
while [ $# -gt 0 ]; do
  case "$1" in
    --product-name) name="${2:-}"; shift 2 ;;
    --product-domain) pdomain="${2:-}"; shift 2 ;;
    --subdomain) sub="${2:-}"; shift 2 ;;
    --watch) watch="${2:-}"; shift 2 ;;
    --domain) zone="${2:-}"; shift 2 ;;
    *) usage ;;
  esac
done
[ -n "$name" ] && [ -n "$pdomain" ] && [ -n "$sub" ] || usage

here="$(cd "$(dirname "$0")" && pwd)"
L="${BASELINE_DIR:-$(cd "$here/../.." && pwd)}"
say() { printf '%s\n' "$*"; }
need() { say "ACTION REQUIRED: $*"; exit 3; }
fail() { say "FAILED: $*"; exit 1; }

# ── where we are: workspace, repository, checkout — from the environment ──
ws="${ORUN_WORKSPACE:-${ORUN_ORG:-}}"
[ -n "$ws" ] || need "this session has no workspace set. Start a new bootstrap session from the console."
full="${ORUN_REPO_FULL_NAME:-}"
if [ -z "$full" ] && top="$(git rev-parse --show-toplevel 2>/dev/null)"; then
  full="$(git -C "$top" config --get remote.origin.url 2>/dev/null | sed -E 's#^(https://github.com/|git@github.com:)##; s#\.git$##')"
fi
[ -n "$full" ] || need "this session is not bound to a product repository. Start a new bootstrap session from the console with the repository selected."
org="${full%%/*}"; repo="${full##*/}"
out=""
if top="$(git rev-parse --show-toplevel 2>/dev/null)" \
   && git -C "$top" config --get remote.origin.url 2>/dev/null | grep -qi "github.com[:/]$full"; then
  out="$top"
fi
if [ -z "$out" ]; then
  for c in "$PWD/$repo" "$HOME/work/$repo" "$HOME/$repo" "${ORUN_REPO_DIR:-}"; do
    [ -n "$c" ] && [ -d "$c/.git" ] && { out="$c"; break; }
  done
fi
[ -n "$out" ] || need "the checkout of $full is not in this sandbox. Start a new bootstrap session; the platform clones it."
cd "$out"

# ── the environment the platform prepared, checked rather than rebuilt ──
tok="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
[ -n "$tok" ] || need "the GitHub credential is missing from this session's environment. Start a new bootstrap session."
[ -n "${ORUN_TOKEN_FILE:-}${ORUN_TOKEN:-}" ] || need "the platform credential is missing from this session's environment. Start a new bootstrap session."
export GH_TOKEN="$tok" GITHUB_TOKEN="$tok"   # gh reads GH_TOKEN; the flows' REST helper reads either
floor="2.55.0"
have="$(orun --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
[ -n "$have" ] || fail "the orun binary is not on PATH in this sandbox."
[ "$(printf '%s\n%s\n' "$floor" "$have" | sort -V | head -1)" = "$floor" ] \
  || fail "orun $have is older than the $floor this baseline needs; the sandbox image is stale. Start a new bootstrap session."
if ! command -v gh >/dev/null 2>&1; then
  say "UPDATE: installing the GitHub CLI the build uses."
  ghv="$(curl -fsSI --max-time 30 https://github.com/cli/cli/releases/latest 2>/dev/null | tr -d '\r' | sed -nE 's#^[Ll]ocation: .*/tag/v([0-9.]+)$#\1#p' | head -1)"
  [ -n "$ghv" ] || fail "could not resolve the GitHub CLI release to install."
  arch="$(uname -m)"; case "$arch" in x86_64) arch=amd64 ;; aarch64|arm64) arch=arm64 ;; esac
  mkdir -p "$HOME/.local/bin"
  curl -fsSL --max-time 120 "https://github.com/cli/cli/releases/download/v${ghv}/gh_${ghv}_linux_${arch}.tar.gz" \
    | tar -xz -C "$HOME/.local/bin" --strip-components=2 "gh_${ghv}_linux_${arch}/bin/gh" \
    || fail "could not install the GitHub CLI."
  export PATH="$HOME/.local/bin:$PATH"
fi
git config user.name  >/dev/null 2>&1 || git config user.name  "Orun Baseline Builder"
git config user.email >/dev/null 2>&1 || git config user.email "baseline@oruncloud.com"

# ── the build ──
log="$out/.orun-bootstrap.log"; mkdir -p "$(dirname "$log")"; : > "$log"
say "UPDATE: starting the $name build into $full (workspace $ws). Expect about 75 minutes; I will report each phase as it finishes."
start="$(date +%s)"
set +e
orun workflow run "$L/flows/phases/00-all/workflow.yaml" \
  --set "workspace=$ws" --set "reponame=$repo" --set "githuborg=$org" \
  --set "productname=$name" --set "productdomain=$pdomain" --set "subdomain=$sub" \
  --set "out=$out" --set "watch=$watch" --set "domain=$zone" --set "track=true" \
  ${BASELINE_REF:+--set "baselineref=$BASELINE_REF"} 2>&1 \
  | tee -a "$log" \
  | awk '
    BEGIN {
      p["01-scaffold"]="the product repository is scaffolded and pushed; the plan is laid out with a milestone per phase"
      p["02-foundation"]="foundation landed: the product builds and its tests pass on its own CI"
      p["03-infrastructure"]="infrastructure is live: the Supabase project and Cloudflare data plane are provisioned on stage and prod"
      p["04-workers"]="the worker fleet is deployed on stage and prod"
      p["05-edge"]="the edge API answers on stage and prod"
      p["06-console"]="the console is live on stage and prod"
      p["07-domain"]="the custom domain is attached"
      p["08-docs"]="the deployment documentation is committed"
    }
    { print; fflush() }
    /^umbrella: ✓ 0[0-9]-[a-z]+ complete$/ { n=$3; if (n in p && !seen[n]++) { print "UPDATE: " p[n]; fflush() } }
    /^ACTION REQUIRED: / { fflush() }
  '
rc="${PIPESTATUS[0]}"
set -e

if [ "$rc" -ne 0 ]; then
  if grep -q '^ACTION REQUIRED: ' "$log"; then
    say "$(grep '^ACTION REQUIRED: ' "$log" | tail -1)"
    exit 3
  fi
  phase="$(grep -oE 'umbrella: phase [0-9a-z-]+ FAILED' "$log" | tail -1 | awk '{print $3}')"
  say "FAILED: ${phase:-the build} did not complete. The lines just above this one say why."
  say "  If they name something only the operator can do (connect an integration, allow-list the repository, grant a permission, raise a limit), tell the operator, wait for them, then run this same command again."
  say "  Otherwise run this same command again once; finished phases are skipped in seconds. If it fails at the same place twice, post the last 30 lines of output and stop."
  exit 1
fi

# ── the summary the agent posts ──
say "DONE"
say "── Summary: $name ($full)"
"$L/flows/common/verify-endpoints.sh" "$out" edge console 2>&1 | grep -E '^[✓✕]' || true
export ws
if roll="$("$L/flows/common/track.sh" rollup infra-baselining 2>/dev/null)" && [ -n "$roll" ]; then
  say "tracking: $roll — epic \"Infra baselining — $name\" in the console (Work → Epics)"
fi
say "duration: $(( ( $(date +%s) - start ) / 60 )) minutes"
say "documentation: ai/context/deployment.md (what exists) and ai/context/operations.md (how to operate it), on main"
say "next: rotate the bootstrap credentials; the epic is the audit trail — keep it."
