#!/usr/bin/env bash
# tooling/deploy/fleet-stubs.mjs, against a fake Cloudflare API: it names
# every binding target of the environment, uploads a placeholder for exactly
# the missing ones (never for one that exists), does nothing on a live
# product, refuses to guess when the existence check errors, and the fleet's
# binding holders all wait on the worker whose pre-deploy runs it.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/.." && pwd)"
tool="$root/tooling/deploy/fleet-stubs.mjs"
fail=0
ok() { echo "   ok  $1"; }
bad() { echo "   ✕  $1" >&2; fail=1; }

tmp="$(mktemp -d)"
cleanup() { [ -n "${srv:-}" ] && kill "$srv" 2>/dev/null; rm -rf "$tmp"; }
trap cleanup EXIT

echo "── targets"
node "$tool" --root "$root" --env stage --list > "$tmp/stage"
node "$tool" --root "$root" --env prod --list > "$tmp/prod"
[ "$(wc -l < "$tmp/stage")" -ge 10 ] && ok "stage names the fleet's binding targets ($(wc -l < "$tmp/stage"))" || bad "stage names the fleet's binding targets"
grep -q -- '-membership-worker-stage$' "$tmp/stage" && ok "a stage target carries the -stage suffix" || bad "a stage target carries the -stage suffix"
! grep -q -- '-stage$' "$tmp/prod" && ok "prod names no stage Worker" || bad "prod names no stage Worker"
[ -z "$(node "$tool" --root "$root" --env dev --list)" ] && ok "dev binds nothing, so it stubs nothing" || bad "dev binds nothing, so it stubs nothing"

# A fake API: GET .../scripts/<name>/settings answers 200 for names in
# $tmp/exists, 404 otherwise (500 for a name containing "boom"); PUT
# .../scripts/<name> records the name and its upload in $tmp/puts.
cat > "$tmp/api.mjs" <<'JS'
import http from "node:http";
import fs from "node:fs";
const dir = process.argv[2];
const server = http.createServer((req, res) => {
  let body = "";
  req.on("data", (c) => (body += c));
  req.on("end", () => {
    if (req.headers.authorization !== "Bearer t0k") { res.writeHead(403); return res.end("auth"); }
    const m = req.url.match(/^\/client\/v4\/accounts\/acct\/workers\/scripts\/([^/]+)(\/settings)?$/);
    if (!m) { res.writeHead(400); return res.end("url"); }
    const name = decodeURIComponent(m[1]);
    const exists = fs.readFileSync(`${dir}/exists`, "utf8").split("\n").includes(name);
    if (req.method === "GET" && m[2]) {
      if (name.includes("boom")) { res.writeHead(500); return res.end("upstream"); }
      res.writeHead(exists ? 200 : 404); return res.end("{}");
    }
    if (req.method === "PUT" && !m[2]) {
      fs.appendFileSync(`${dir}/puts`, `${name}\n`);
      fs.writeFileSync(`${dir}/upload-${name}`, body);
      res.writeHead(200); return res.end("{}");
    }
    res.writeHead(405); res.end();
  });
});
server.listen(0, "127.0.0.1", () => fs.writeFileSync(`${dir}/port`, String(server.address().port)));
JS
: > "$tmp/exists"; : > "$tmp/puts"
node "$tmp/api.mjs" "$tmp" & srv=$!
for _ in $(seq 1 50); do [ -s "$tmp/port" ] && break; sleep 0.1; done
export CLOUDFLARE_API_BASE_URL="http://127.0.0.1:$(cat "$tmp/port")/client/v4"
export CLOUDFLARE_ACCOUNT_ID=acct CLOUDFLARE_API_TOKEN=t0k

echo "── a fresh account: every target is created"
ORUN_ENVIRONMENT=stage node "$tool" --root "$root" > "$tmp/out"
cmp -s <(sort "$tmp/puts") "$tmp/stage" && ok "one placeholder per missing target, no others" || bad "one placeholder per missing target, no others"
f="$tmp/upload-$(head -1 "$tmp/stage")"
grep -q '"main_module":"stub.mjs"' "$f" && grep -q 'export default' "$f" && ok "the upload is a module Worker with metadata" || bad "the upload is a module Worker with metadata"

echo "── a half-built account: only the missing ones"
head -4 "$tmp/stage" > "$tmp/exists"; : > "$tmp/puts"
ORUN_ENVIRONMENT=stage node "$tool" --root "$root" >/dev/null
cmp -s <(sort "$tmp/puts") <(tail -n +5 "$tmp/stage") && ok "an existing Worker is never replaced" || bad "an existing Worker is never replaced"

echo "── a live product: nothing"
cp "$tmp/stage" "$tmp/exists"; : > "$tmp/puts"
ORUN_ENVIRONMENT=stage node "$tool" --root "$root" > "$tmp/out"
[ ! -s "$tmp/puts" ] && grep -q "nothing to do" "$tmp/out" && ok "uploads nothing when every target exists" || bad "uploads nothing when every target exists"

echo "── refusals"
CLOUDFLARE_API_TOKEN=wrong ORUN_ENVIRONMENT=stage node "$tool" --root "$root" >/dev/null 2>&1 && bad "an unexpected check answer (403) fails" || ok "an unexpected check answer (403) fails"
env -u ORUN_ENVIRONMENT node "$tool" --root "$root" >/dev/null 2>&1 && bad "no environment fails" || ok "no environment fails"

echo "── the plan's side: every binding holder waits on policy-worker on main"
holders=0; missing=""
for t in "$root"/apps/*/wrangler.template.jsonc "$root"/apps/*/wrangler.jsonc; do
  [ -f "$t" ] || continue
  grep -q '"services"' "$t" || continue
  app="$(basename "$(dirname "$t")")"; holders=$((holders + 1))
  python3 - "$root/apps/$app/component.yaml" <<'PY' || missing="$missing $app"
import sys, yaml
spec = yaml.safe_load(open(sys.argv[1]))["spec"]
deps = {d["component"]: d for d in spec.get("dependsOn", [])}
assert deps.get("policy-worker", {}).get("mode") == "enforced", deps.keys()
PY
done
[ -z "$missing" ] && ok "all $holders binding holders depend on policy-worker, enforced" || bad "not enforced on policy-worker:$missing"
grep -q 'fleet-stubs.mjs' "$root/apps/policy-worker/component.yaml" && ok "policy-worker's pre-deploy runs the tool" || bad "policy-worker's pre-deploy runs the tool"
! grep -q '"services"' "$root/apps/policy-worker/wrangler.jsonc" 2>/dev/null && ok "policy-worker itself binds nothing" || bad "policy-worker itself binds nothing"

exit "$fail"
