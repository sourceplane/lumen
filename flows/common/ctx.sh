#!/usr/bin/env bash
# Sourced by every phase step AFTER the inline baseline resolve (which sets
# $L): resolves the PRODUCT repo dir ($P) and prepares headless git.
#
#   . "$L/flows/common/ctx.sh" <workspace> <repo-or-empty> <out-or-empty>
#
# Product resolution: an explicit `out` path wins (local mode); otherwise a
# `repo` (owner/name) is cloned into $PWD/product — the headless container
# mode, authenticated through gh's git credential helper, which honors
# GH_TOKEN/GITHUB_TOKEN. Idempotent: an existing clone is reused and
# fast-forwarded. Also ensures a git identity exists for phase commits
# (bootstrap bot fallback) and wires the credential helper for pushes.
ws="${1:?ctx.sh: workspace required}"
ctx_repo="${2:-}"
ctx_out="${3:-}"

if [ -n "$ctx_out" ]; then
  P="$ctx_out"
elif [ -n "$ctx_repo" ]; then
  case "$PWD" in */.orun/wfruns/*) W="${PWD%%/.orun/wfruns/*}" ;; *) W="$PWD" ;; esac
  P="$W/product"
  if [ ! -e "$P/.git" ]; then
    echo "fetching product repo $ctx_repo"
    git clone -q --config credential.helper= \
      --config 'credential.helper=!f(){ [ "$1" = get ] && exec gh auth git-credential get; :; }; f' \
      --config http.lowSpeedLimit=1000 --config http.lowSpeedTime=30 \
      "https://github.com/$ctx_repo" "$P"
  else
    git -C "$P" checkout -q main 2>/dev/null || true
    # Stall timeout on the network op: git has NO default transfer timeout,
    # and a wedged connection here once hung a step until the runner's
    # kill — long past its declared timeout (71m, live). Failure is
    # tolerated (the clone may simply be current) but said out loud.
    git -C "$P" -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=30 pull -q --ff-only 2>/dev/null \
      || echo "ctx: product pull did not fast-forward (offline or diverged) — continuing with the existing clone"
  fi
else
  echo "ctx: pass --set out=<path> (local checkout mode) or --set repo=<owner/name> (headless clone mode)" >&2
  exit 1
fi

if [ -d "$P/.git" ]; then
  # get-only helper: gh answers `get` from GH_TOKEN/GITHUB_TOKEN; store and
  # erase are swallowed. A store attempt in a keychain-less HOME either
  # errors (-60006 noise) or — worse — raises securityd's BLOCKING
  # "Keychain Not Found" dialog on the console user's screen, hanging the
  # step until a human clicks (hit live, twice).
  # The leading EMPTY helper resets git's helper list — otherwise a system/
  # global osxkeychain helper still fires on store (git runs every helper).
  git -C "$P" config --replace-all credential.helper "" 2>/dev/null || true
  git -C "$P" config --add credential.helper '!f(){ [ "$1" = get ] && exec gh auth git-credential get; :; }; f' 2>/dev/null || true
  if ! git -C "$P" config user.email >/dev/null 2>&1 \
      && ! git config --global user.email >/dev/null 2>&1; then
    git -C "$P" config user.email "bootstrap-bot@users.noreply.github.com"
    git -C "$P" config user.name "bootstrap-bot"
  fi
fi

export L P ws
