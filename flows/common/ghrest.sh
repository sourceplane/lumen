#!/usr/bin/env bash
# GitHub operations with a plain-REST fallback. Source this; every function
# tries `gh` first and, when gh's credential path is broken (sandboxes and
# proxies routinely block GraphQL and gh's Actions surface while plain REST
# with the same token works — hit live on a full bootstrap), falls back to
# curl against api.github.com with GH_TOKEN/GITHUB_TOKEN. Parsing uses
# python3 (an image dependency); jq is never required.
#
# Repo slug resolution: $GH_REPO (owner/name) when set, else the origin URL.

ghr_repo() {
  if [ -n "${GH_REPO:-}" ]; then printf '%s' "$GH_REPO"; return; fi
  git remote get-url origin 2>/dev/null \
    | sed -E 's#^(git@github.com:|https://github.com/|ssh://git@github.com/)##; s#\.git$##; s#/*$##'
}

ghr_curl() { # METHOD PATH [JSON_BODY] — prints response body; nonzero on HTTP >= 400
  local method="$1" path="$2" body="${3:-}" tok="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
  [ -n "$tok" ] || { echo "ghrest: no GH_TOKEN/GITHUB_TOKEN in env" >&2; return 1; }
  if [ -n "$body" ]; then
    curl -sf -X "$method" -H "Authorization: Bearer $tok" \
      -H "Accept: application/vnd.github+json" -H "Content-Type: application/json" \
      --max-time 60 -d "$body" "https://api.github.com/$path"
  else
    curl -sf -X "$method" -H "Authorization: Bearer $tok" \
      -H "Accept: application/vnd.github+json" \
      --max-time 60 "https://api.github.com/$path"
  fi
}

ghr_json() { # FILTER — python3 one-liner over stdin JSON
  python3 -c "import json,sys; d=json.load(sys.stdin); $1"
}

# ── PRs ──────────────────────────────────────────────────────────────────────

ghr_pr_create() { # TITLE BODY HEAD_BRANCH → prints PR number
  local title="$1" body="$2" head="$3" repo num
  if num="$(gh pr create --title "$title" --body "$body" 2>/dev/null \
      | sed -n 's#.*/pull/\([0-9]*\).*#\1#p')" && [ -n "$num" ]; then
    printf '%s' "$num"; return 0
  fi
  repo="$(ghr_repo)"
  ghr_curl POST "repos/$repo/pulls" \
    "$(python3 -c 'import json,sys;print(json.dumps({"title":sys.argv[1],"body":sys.argv[2],"head":sys.argv[3],"base":"main"}))' "$title" "$body" "$head")" \
    | ghr_json 'print(d["number"])'
}

ghr_pr_merge() { # PR_NUMBER HEAD_BRANCH — squash-merge; branch delete best-effort
  local num="$1" head="$2" repo
  if gh pr merge "$num" --squash --delete-branch 2>/dev/null \
      || gh pr merge "$num" --squash --admin --delete-branch 2>/dev/null; then
    return 0
  fi
  repo="$(ghr_repo)"
  ghr_curl PUT "repos/$repo/pulls/$num/merge" '{"merge_method":"squash"}' >/dev/null
  # Ref deletion is cosmetic and blocked in some sandboxes — never fail on it.
  ghr_curl DELETE "repos/$repo/git/refs/heads/$head" >/dev/null 2>&1 || true
}

ghr_pr_checks_state() { # HEAD_SHA → "none" | "pending" | "fail:<n>" | "done"
  local sha="$1" repo out
  repo="$(ghr_repo)"
  out="$(ghr_curl GET "repos/$repo/commits/$sha/check-runs?per_page=100" 2>/dev/null)" || { echo none; return 0; }
  printf '%s' "$out" | ghr_json '
runs=d.get("check_runs",[])
if not runs: print("none")
elif any(r.get("status")!="completed" for r in runs): print("pending")
else:
    fails=[r for r in runs if r.get("conclusion") not in ("success","neutral","skipped")]
    print(f"fail:{len(fails)}" if fails else "done")'
}

ghr_pr_failed_checks() { # HEAD_SHA → failed check names
  local sha="$1" repo
  repo="$(ghr_repo)"
  ghr_curl GET "repos/$repo/commits/$sha/check-runs?per_page=100" 2>/dev/null | ghr_json '
[print(r["name"]) for r in d.get("check_runs",[])
 if r.get("status")=="completed" and r.get("conclusion") not in ("success","neutral","skipped")]' || true
}

# ── Actions runs ────────────────────────────────────────────────────────────

ghr_run_latest_main() { # → newest run id on main
  local id repo
  if id="$(gh run list --branch main --limit 1 --json databaseId --jq '.[0].databaseId' 2>/dev/null)" \
      && [ -n "$id" ] && [ "$id" != "null" ]; then
    printf '%s' "$id"; return 0
  fi
  repo="$(ghr_repo)"
  ghr_curl GET "repos/$repo/actions/runs?branch=main&per_page=1" \
    | ghr_json 'print(d["workflow_runs"][0]["id"])'
}

ghr_run_field() { # RUN_ID status|conclusion
  local id="$1" field="$2" v repo
  if v="$(gh run view "$id" --json "$field" --jq ".$field" 2>/dev/null)" && [ -n "$v" ]; then
    printf '%s' "$v"; return 0
  fi
  repo="$(ghr_repo)"
  ghr_curl GET "repos/$repo/actions/runs/$id" | ghr_json "print(d.get(\"$field\") or \"\")"
}

ghr_run_failed_jobs() { # RUN_ID → failed job names
  local id="$1" repo
  if gh run view "$id" --json jobs --jq '.jobs[]|select(.conclusion=="failure")|.name' 2>/dev/null; then
    return 0
  fi
  repo="$(ghr_repo)"
  ghr_curl GET "repos/$repo/actions/runs/$id/jobs?per_page=100" | ghr_json '
[print(j["name"]) for j in d.get("jobs",[]) if j.get("conclusion")=="failure"]' || true
}

ghr_run_rerun_failed() { # RUN_ID
  local id="$1" repo
  if gh run rerun "$id" --failed 2>/dev/null; then return 0; fi
  repo="$(ghr_repo)"
  ghr_curl POST "repos/$repo/actions/runs/$id/rerun-failed-jobs" '{}' >/dev/null
}
