#!/usr/bin/env bash
# The bootstrap's hand on the task plane (saas-baseline-tracking BT1). One
# client — `orun` — and five verbs, each idempotent by IDENTITY (epic by
# slug, milestone by name-within-epic, task by title-within-epic), never by
# memory: a re-run finds what it made before and prints the same handle.
#
#   flows/common/track.sh ensure-epic      <slug> <name> [description]
#   flows/common/track.sh ensure-milestone <epic> <phase-dir>          # 03-infrastructure → "03 — infrastructure" + its exit criteria
#   flows/common/track.sh ensure-task      <epic> <phase-dir> <title> <contract-file> [brief]
#   flows/common/track.sh rollup           <epic>
#   flows/common/track.sh verdict          <key>
#
# Contract (the callers depend on it): ONE line on stdout — the handle
# (slug / mls_… / KEY / the rollup line / "rung — reason") — and prose on
# stderr. Tracking never blocks a landing: when the binary predates the
# task-plane verbs (`orun task epic`), the plane refuses, or the workspace
# is unknown, the verb says so ONCE on stderr, records the reason in the
# run's cache, and exits 0 with an EMPTY stdout. Callers treat empty as "no
# handle" and land untracked, exactly as before BT.
#
# Workspace: $ws (exported by ctx.sh) or TRACK_WORKSPACE. Cache:
# $TRACK_WORKDIR/tracking.json — default ${XDG_CACHE_HOME:-~/.cache}/
# orun-bootstrap/<workspace>/, never the baseline or product tree (product
# content stays product-only; a baseline checkout stays clean). Read
# first, re-verified against the plane only when a cached handle is stale.
set -euo pipefail

verb="${1:-}"; shift || true
ws="${ws:-${TRACK_WORKSPACE:-}}"

# ── the run's cache ──────────────────────────────────────────────────────
if [ -z "${TRACK_WORKDIR:-}" ]; then
  TRACK_WORKDIR="${XDG_CACHE_HOME:-$HOME/.cache}/orun-bootstrap/${ws:-no-workspace}"
fi
mkdir -p "$TRACK_WORKDIR"
cache="$TRACK_WORKDIR/tracking.json"
[ -f "$cache" ] || printf '{"epic":null,"milestones":{},"tasks":{},"refused":null}\n' > "$cache"

cache_get() { # PATH… → value or empty
  python3 - "$cache" "$@" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
for k in sys.argv[2:]:
    d=d.get(k) if isinstance(d,dict) else None
    if d is None: break
print(d if isinstance(d,str) else "")
PY
}
cache_set() { # KEY [SUBKEY] VALUE
  python3 - "$cache" "$@" <<'PY'
import json,sys
p=sys.argv[1]; d=json.load(open(p)); a=sys.argv[2:]
if len(a)==2: d[a[0]]=a[1] if a[1]!="null" else None
else: d.setdefault(a[0],{})[a[1]]=a[2]
json.dump(d,open(p,"w"))
PY
}

# ── degradation: say it once, remember it, hand back nothing ─────────────
untracked() { # REASON
  if [ -z "$(cache_get refused)" ]; then
    echo "track: $1 — landing untracked (upgrade orun to a release carrying \`orun task epic\`, and grant task.write to the run's principal)" >&2
    cache_set refused "$1"
  fi
  exit 0
}
[ -n "$verb" ] || { echo "usage: track.sh ensure-epic|ensure-milestone|ensure-task|rollup|verdict …" >&2; exit 2; }
[ -n "$ws" ] || untracked "no workspace (\$ws / TRACK_WORKSPACE unset)"
command -v orun >/dev/null 2>&1 || untracked "orun not on PATH"
orun task epic --help >/dev/null 2>&1 || untracked "this orun predates the task-plane verbs"

# One place for every orun call: --json, the workspace, stderr kept.
run_orun() { orun "$@" --workspace "$ws" --json; }
jget() { # JSON-on-stdin, PATH… → value or empty (dicts/lists as JSON)
  python3 -c '
import json,sys
try: d=json.load(sys.stdin)
except Exception: print(""); sys.exit(0)
for k in sys.argv[1:]:
    d=d.get(k) if isinstance(d,dict) else None
    if d is None: break
if d is None: print("")
elif isinstance(d,(dict,list)): print(json.dumps(d))
else: print(d)' "$@"
}

# ── the phase table: milestone name + exit criteria per phase dir ────────
# (the "verified by" column of flows/phases/README.md, as data)
phase_name() { # 03-infrastructure → "03 — infrastructure"
  local n="${1%%-*}" rest="${1#*-}"
  printf '%s — %s' "$n" "$rest"
}
phase_exit_criteria() { # phase-dir → one criterion per line
  case "$1" in
    01-scaffold)        printf '%s\n' "repo pushed and main pinned as default" "workspace linked (orun cloud link)" ;;
    02-foundation)      printf '%s\n' "PR verify lanes green (turbo builds + tests)" ;;
    03-infrastructure)  printf '%s\n' "WIRING_CLOUDFLARE_KV, WIRING_CLOUDFLARE_HYPERDRIVE and SUPABASE_PROJECT_REF published on stage and prod" ;;
    04-workers)         printf '%s\n' "both landings converged" "service-binding feedback edges restored" ;;
    05-edge)            printf '%s\n' "api-edge /health 200 on stage and prod" ;;
    06-console)         printf '%s\n' "console and edge live on stage and prod" ;;
    07-domain)          printf '%s\n' "convergence green on the custom domain" ;;
    08-docs)            printf '%s\n' "committed deployment manifest matches probed reality" ;;
    *)                  ;;
  esac
}

ensure_epic() { # SLUG NAME [DESCRIPTION]
  local slug="${1:?slug}" name="${2:?name}" desc="${3:-}" out
  if [ "$(cache_get epic)" = "$slug" ]; then echo "$slug"; return; fi
  local args=(task epic create --slug "$slug" --name "$name")
  [ -z "$desc" ] || args+=(--description "$desc")
  if ! out="$(run_orun "${args[@]}" 2>/dev/null)"; then untracked "epic create refused"; fi
  if [ "$(printf '%s' "$out" | jget existed)" = "True" ] || [ "$(printf '%s' "$out" | jget existed)" = "true" ]; then
    echo "track: epic $slug already exists — reusing it" >&2
  else
    echo "track: epic $slug created ($(printf '%s' "$out" | jget epic key))" >&2
  fi
  cache_set epic "$slug"
  echo "$slug"
}

ensure_milestone() { # EPIC PHASE-DIR → mls_…
  local epic="${1:?epic}" phase="${2:?phase-dir}" name id out
  name="$(phase_name "$phase")"
  id="$(cache_get milestones "$phase")"
  [ -z "$id" ] || { echo "$id"; return; }
  # Find by name within the epic first — the same name twice is two phases.
  if ! out="$(run_orun task epic show "$epic" 2>/dev/null)"; then untracked "epic $epic unreadable"; fi
  id="$(printf '%s' "$out" | python3 -c '
import json,sys; want=sys.argv[1]
try: d=json.load(sys.stdin)
except Exception: d={}
for m in d.get("milestones") or []:
    if m.get("name")==want: print(m.get("id","")); break' "$name")"
  if [ -z "$id" ]; then
    local args=(task milestone create --epic "$epic" --name "$name")
    while IFS= read -r c; do [ -z "$c" ] || args+=(--exit-criteria "$c"); done < <(phase_exit_criteria "$phase")
    if ! out="$(run_orun "${args[@]}" 2>/dev/null)"; then untracked "milestone create refused"; fi
    id="$(printf '%s' "$out" | jget milestone id)"
    [ -n "$id" ] || untracked "milestone create returned no id"
    echo "track: milestone \"$name\" created ($id)" >&2
  else
    echo "track: milestone \"$name\" exists ($id) — reusing it" >&2
  fi
  cache_set milestones "$phase" "$id"
  echo "$id"
}

ensure_task() { # EPIC PHASE-DIR TITLE CONTRACT-FILE [BRIEF] → KEY
  local epic="${1:?epic}" phase="${2:?phase-dir}" title="${3:?title}" contract="${4:?contract-file}" brief="${5:-}" key mls out
  key="$(cache_get tasks "$title")"
  [ -z "$key" ] || { echo "$key"; return; }
  [ -f "$contract" ] || untracked "contract template missing: $contract"
  mls="$(ensure_milestone "$epic" "$phase")"
  [ -n "$mls" ] || exit 0 # ensure_milestone already said why
  # Find by title within the epic: the landing's PR title is the identity.
  if ! out="$(run_orun task list --epic "$epic" 2>/dev/null)"; then untracked "task list refused"; fi
  key="$(printf '%s' "$out" | python3 -c '
import json,sys; want=sys.argv[1]
try: d=json.load(sys.stdin)
except Exception: d={}
for t in d.get("tasks") or []:
    if t.get("titleMirror")==want: print(t.get("key","")); break' "$title")"
  if [ -z "$key" ]; then
    local args=(task create --prefix BASE --title "$title" --epic "$epic" --milestone "$mls" --assignee me --contract "$contract")
    [ -z "$brief" ] || args+=(--brief "$brief")
    if ! out="$(run_orun "${args[@]}" 2>/dev/null)"; then untracked "task create refused"; fi
    key="$(printf '%s' "$out" | jget task key)"
    [ -n "$key" ] || untracked "task create returned no key"
    echo "track: task $key created for \"$title\" (contract $(printf '%s' "$out" | jget contractHash | cut -c1-15)…; branch orun/$key-$phase)" >&2
  else
    echo "track: task $key exists for \"$title\" — reusing it" >&2
  fi
  cache_set tasks "$title" "$key"
  echo "$key"
}

rollup() { # EPIC → "N/M done · <phase>: a/b …"
  local epic="${1:?epic}" out
  if ! out="$(run_orun task epic show "$epic" 2>/dev/null)"; then untracked "epic $epic unreadable"; fi
  printf '%s' "$out" | python3 -c '
import json,sys
try: d=json.load(sys.stdin)
except Exception: print(""); sys.exit(0)
r=d.get("rollup") or {}
parts=["%d/%d done" % (r.get("done",0), r.get("total",0))]
for m in r.get("milestones") or []:
    parts.append("%s: %d/%d" % (m.get("name") or m.get("id"), m.get("done",0), m.get("total",0)))
print(" · ".join(parts))'
}

verdict() { # KEY → "rung — reason"
  local key="${1:?key}" out
  if ! out="$(run_orun task show "$key" 2>/dev/null)"; then untracked "task $key unreadable"; fi
  printf '%s' "$out" | python3 -c '
import json,sys
try: d=json.load(sys.stdin)
except Exception: print(""); sys.exit(0)
v=(d.get("verdict") or {}).get("verdict") or {}
print("%s — %s" % (v.get("rung","?"), (v.get("evidence") or {}).get("reason","")))'
}

case "$verb" in
  ensure-epic)      ensure_epic "$@" ;;
  ensure-milestone) ensure_milestone "$@" ;;
  ensure-task)      ensure_task "$@" ;;
  rollup)           rollup "$@" ;;
  verdict)          verdict "$@" ;;
  *) echo "track.sh: unknown verb $verb" >&2; exit 2 ;;
esac
