#!/usr/bin/env bash
# Phase sequencing for the bootstrap umbrella (flows/phases/00-all): the
# checkpoint, the cold-resume probes, and the run_phase that skips work already
# done. Sourced by every umbrella step AFTER the inline baseline resolve:
#
#   . "$L/flows/common/umbrella.sh"
#
# Expects in the environment: L (baseline checkout), W (workdir anchor),
# out (product dir), ws (workspace), plus the umbrella's own inputs exported
# as UMB_* by the caller.
#
# ── WHY RESUMING MATTERS ──────────────────────────────────────────────────
#
# The umbrella used to have exactly one recovery move: run it again from the
# top. Every phase is idempotent, so that is SAFE — but it is neither cheap nor
# sufficient, and on a partially-deployed product it is actively wrong:
#
#  1. Cost. Re-running 01→04 to reach a failure in 05 costs ~45 minutes of
#     wall-clock and a full CI fan-out, every attempt.
#  2. Correctness. Git-level idempotence is not deploy-level idempotence. CI
#     plans `--changed`; re-applying identical content produces an EMPTY plan,
#     so components that failed to deploy the first time are never retried.
#     A partial fleet stays partial through unlimited restarts (see
#     redeploy-marker.sh for the live case this comes from).
#
# So resume is two things, and both are needed: skip what is genuinely done,
# and force a real deploy for what only LOOKS done.
#
# ── WHERE THE CHECKPOINT LIVES ────────────────────────────────────────────
#
# $W/.orun/bootstrap/state — beside baseline/ and product/, outside the product
# repo (nothing about a bootstrap run belongs in the product's history).
#
# A local file only helps when the workdir is reused. Headless re-runs get a
# fresh container, so the checkpoint is a CACHE, never the source of truth:
# when it is absent, phase_is_complete() reconstructs the answer by PROBING
# REALITY (the repo on main, the workspace's secrets, the live endpoints).
# Reality survives container death; a state file does not.
set -uo pipefail

# Under .orun/ so the baseline's own .gitignore (".orun/*") already covers it —
# in local mode $W IS the baseline checkout, and an untracked state file there
# would show up in every `git status` and risk being swept into a landing.
BOOTSTRAP_STATE_DIR="${W:?umbrella.sh: W (workdir anchor) required}/.orun/bootstrap"
BOOTSTRAP_STATE="$BOOTSTRAP_STATE_DIR/state"

# All phases in order — the resume ordering and the `from` input both read it.
UMBRELLA_PHASES="01-scaffold 02-foundation 03-infrastructure 04-workers 05-edge 06-console 07-domain 08-docs"

# ── checkpoint primitives ────────────────────────────────────────────────

bs_init() { mkdir -p "$BOOTSTRAP_STATE_DIR"; [ -f "$BOOTSTRAP_STATE" ] || : > "$BOOTSTRAP_STATE"; }

bs_status() {  # bs_status <phase> → prints done|failed|""
  bs_init
  awk -v p="$1" '$1 == p { s = $2 } END { print s }' "$BOOTSTRAP_STATE"
}

bs_mark() {  # bs_mark <phase> <done|failed>
  bs_init
  local phase="$1" status="$2" tmp
  tmp="$(mktemp)"
  grep -v "^$phase " "$BOOTSTRAP_STATE" > "$tmp" 2>/dev/null || true
  printf '%s %s %s\n' "$phase" "$status" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$tmp"
  mv "$tmp" "$BOOTSTRAP_STATE"
}

bs_reset() { bs_init; : > "$BOOTSTRAP_STATE"; echo "umbrella: checkpoint cleared — every phase will run"; }

# ── reality probes (the cold-resume path) ────────────────────────────────
#
# Each answers ONE question: is this phase's observable postcondition true?
# They must be conservative — a false "complete" skips a phase that never ran,
# which is the expensive direction. When a probe cannot tell, it says no.

_UMB_FETCHED=false
_fetch_once() {  # refresh origin/main once per step — the probes read it
  [ -d "$out/.git" ] || return 1
  [ "$_UMB_FETCHED" = "true" ] && return 0
  git -C "$out" -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=30 \
    fetch -q origin main 2>/dev/null || true
  _UMB_FETCHED=true
  return 0
}

_repo_has() {  # _repo_has <path-in-repo> — is it on the product's main?
  _fetch_once || return 1
  git -C "$out" cat-file -e "origin/main:$1" 2>/dev/null
}

_secret_present() {  # _secret_present <env> <key>
  # From $out: orun discovers intent.yaml relative to the CWD, and run_phase
  # does not chdir — probing from the workdir listed nothing and reported a
  # complete phase 03 as incomplete.
  #
  # Capture then match, never `orun … | grep -q`: grep exits on first match,
  # orun takes SIGPIPE, and pipefail turns that into a failure (see the same
  # trap in preflight.sh). Here it would only cost a redundant phase re-run,
  # but the pattern is wrong either way.
  local listing
  listing="$( cd "$out" 2>/dev/null && orun secrets list --org "$ws" --env "$1" 2>/dev/null || true )"
  case "$listing" in *"$2"*) return 0 ;; *) return 1 ;; esac
}

_url_code() { curl -s -o /dev/null -w '%{http_code}' --max-time 15 "$1" 2>/dev/null || echo 000; }

_edge_live() {  # both envs serving /health
  local repo sub code
  repo="$(_vals repoName)"; sub="$(_vals workersDevSubdomain)"
  [ -n "$repo" ] && [ -n "$sub" ] || return 1
  for env in stage prod; do
    code="$(_url_code "https://${repo}-api-edge-${env}.${sub}.workers.dev/health")"
    [ "$code" = "200" ] || return 1
  done
  return 0
}

_console_live() {
  local repo sub code
  repo="$(_vals repoName)"; sub="$(_vals workersDevSubdomain)"
  [ -n "$repo" ] && [ -n "$sub" ] || return 1
  for env in stage prod; do
    code="$(_url_code "https://${repo}-web-console-next-${env}.${sub}.workers.dev")"
    [ "$code" -ge 200 ] 2>/dev/null && [ "$code" -lt 400 ] || return 1
  done
  return 0
}

_vals() {  # read a key out of the product's .rebrand/values.json
  python3 -c "import json,sys;print(json.load(open('$out/.rebrand/values.json')).get('$1',''))" 2>/dev/null || true
}

phase_is_complete() {  # phase_is_complete <phase> → 0 when the postcondition holds
  local phase="$1"
  case "$phase" in
    01-scaffold)
      # The repo exists, carries its identity, and is linked to the workspace.
      _repo_has .rebrand/values.json && _repo_has intent.yaml
      ;;
    02-foundation)
      _repo_has packages/db/component.yaml && _repo_has packages/shared/component.yaml
      ;;
    03-infrastructure)
      # The infra phase's real output is the published wiring — every later
      # deploy resolves these, so their presence is the honest postcondition.
      local env key
      for env in stage prod; do
        for key in WIRING_CLOUDFLARE_KV WIRING_CLOUDFLARE_HYPERDRIVE SUPABASE_PROJECT_REF; do
          _secret_present "$env" "$key" || return 1
        done
      done
      return 0
      ;;
    04-workers)
      # Content on main is necessary but NOT sufficient — the fleet may be
      # committed and undeployed. Internal workers set workers_dev:false and
      # cannot be probed from outside the account, so we lean on an invariant
      # the platform enforces for us: api-edge binds every worker as a service
      # binding, and Cloudflare REFUSES the api-edge deploy if any target is
      # missing (error 10143). A live api-edge on both envs is therefore proof
      # the whole fleet exists. No live api-edge → we cannot claim the fleet,
      # and the phase re-runs with redeploy markers.
      _repo_has apps/metering-worker/component.yaml \
        && _repo_has apps/api-edge/component.yaml \
        && _edge_live
      ;;
    05-edge)
      _repo_has apps/api-edge/component.yaml && _edge_live
      ;;
    06-console)
      _repo_has apps/web-console-next/component.yaml && _console_live
      ;;
    07-domain)
      # No cheap, unambiguous probe (the zone may be mid-propagation), so the
      # checkpoint is the only evidence — an unresumed 07 simply re-runs.
      return 1
      ;;
    08-docs)
      _repo_has ai/context/deployment.md \
        && ! git -C "$out" grep -q "TBD_08DOCS" origin/main -- ai/context README.md 2>/dev/null
      ;;
    *) return 1 ;;
  esac
}

# ── components each phase deploys (for redeploy markers on retry) ────────

# Directories holding a component.yaml that this phase is responsible for
# deploying. Always exits 0 — an empty list is a valid answer (phase 01 and 08
# deploy nothing), and a non-zero return here would trip the caller's `set -e`.
phase_components() {
  case "$1" in
    02-foundation)     _comp_dirs packages ;;
    03-infrastructure) _comp_dirs infra ;;
    04-workers)        _comp_dirs apps '*-worker' ;;
    05-edge)           echo apps/api-edge ;;
    06-console)        echo apps/web-console-next ;;
  esac
  return 0
}

_comp_dirs() {  # _comp_dirs <root> [name-glob] — dirs under $out/<root> with a component.yaml
  local root="$1" glob="${2:-*}"
  [ -d "$out/$root" ] || return 0
  ( cd "$out" && find "$root" -name component.yaml -not -path '*/node_modules/*' \
      -print 2>/dev/null | sed 's:/component.yaml$::' ) \
    | while read -r d; do
        case "${d##*/}" in $glob) echo "$d" ;; esac
      done
  return 0
}

# ── the sequencer ────────────────────────────────────────────────────────

# run_phase <name> <attempts> [extra --set args…]
#
# Skips the phase when it is already complete, runs it otherwise, and stamps
# redeploy markers before any attempt that follows a failure — so a retry
# re-deploys instead of re-applying identical content into an empty plan.
run_phase() {
  local name="$1" attempts="$2"; shift 2
  local i w

  # Explicit operator override wins over every probe: `--set from=05-edge`
  # replays from there regardless of what the checkpoint or reality says.
  if [ -n "${UMB_FROM:-}" ] && _phase_lt "$name" "$UMB_FROM"; then
    echo "umbrella: ⏭  $name — before from=$UMB_FROM"
    return 0
  fi

  if [ "${UMB_FRESH:-false}" != "true" ]; then
    if [ "$(bs_status "$name")" = "done" ]; then
      echo "umbrella: ✓ $name — already done this run (checkpoint)"
      return 0
    fi
    if phase_is_complete "$name"; then
      echo "umbrella: ✓ $name — postcondition already holds (probed); recording and skipping"
      bs_mark "$name" done
      return 0
    fi
  fi

  for i in $(seq 1 "$attempts"); do
    if [ "$i" -gt 1 ]; then
      # The retry is only worth anything if it can actually deploy. Put this
      # phase's components back in the changed set before trying again.
      _stamp_for_retry "$name" "attempt $i after a failed convergence"
    fi
    if orun workflow run "$L/flows/phases/$name/workflow.yaml" \
        --set "workspace=$ws" --set "out=$out" \
        --set "dryrun=${UMB_DRYRUN:-false}" "$@"; then
      bs_mark "$name" done
      echo "umbrella: ✓ $name complete"
      return 0
    fi
    if [ "$i" -lt "$attempts" ]; then
      w=$(( i * 60 ))
      echo "umbrella: phase $name attempt $i/$attempts failed — retrying in ${w}s (idempotent)"
      sleep "$w"
    fi
  done

  bs_mark "$name" failed
  cat >&2 <<EOF
umbrella: phase $name FAILED after $attempts attempt(s) — see its last error above
          (the flows print the exact operator action when one is needed).

          Fix the cause, then RESUME — do not start over. Completed phases are
          skipped automatically, or name the restart point explicitly:

            orun workflow run …/flows/phases/00-all/workflow.yaml \\
              --set workspace=$ws --set out=$out --set from=$name
EOF
  return 1
}

_stamp_for_retry() {  # _stamp_for_retry <phase> <reason>
  local name="$1" reason="$2" comps flag
  # ONCE per phase per run. One marker is all it takes to put a component in
  # the changed set; stamping again on attempt 3 only piles duplicate comment
  # lines into component.yaml. It also keeps the noise proportionate when the
  # retry had nothing to do with deploying (a preflight/auth failure retries
  # too, and those attempts should not litter twelve files).
  flag="$BOOTSTRAP_STATE_DIR/stamped-$name"
  [ -f "$flag" ] && return 0
  comps="$(phase_components "$name")"
  [ -n "$comps" ] || return 0
  bs_init
  # shellcheck disable=SC2086
  "$L/flows/common/redeploy-marker.sh" "$out" "$reason" $comps || true
  : > "$flag"
}

_phase_lt() {  # _phase_lt <a> <b> — true when a comes before b in the order
  local a="$1" b="$2" p
  for p in $UMBRELLA_PHASES; do
    [ "$p" = "$b" ] && return 1   # reached b without seeing a → a is not before b
    [ "$p" = "$a" ] && return 0
  done
  return 1
}
