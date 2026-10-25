#!/usr/bin/env bash
# THE PREBUILT CONSOLE IS USED EXACTLY WHEN IT IS THE SAME CODE.
#
# saas-console-artifact CA3/CA4. tag.yml publishes the console — bundled on
# the build machine, because OpenNext's raw output require()s absolute
# build-machine paths — under a hash of the sources that produce it; a bootstrap's 05 phase
# pins it into the product if the baseline's sources have one; the product's
# build command fetches it while its own sources still hash to the pin, and
# builds from source once they don't. This drives the real
# apps/web-console-next/scripts/console-artifact.mjs over a tiny fake
# workspace (no Next.js build) and checks each path, including the one that
# must never be papered over: a tampered asset is a failure, not a rebuild.
# Needs: node, tar, gzip. No network.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"
tool="$root/apps/web-console-next/scripts/console-artifact.mjs"
command -v node >/dev/null || { echo "console-artifact.test.sh needs node" >&2; exit 1; }

fail=0
ok()  { echo "   ok  $*"; }
bad() { echo "   FAIL $*" >&2; fail=1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# A workspace shaped like this repository, with a "built" console.
mkws() {
  local d="$1"
  mkdir -p "$d/apps/web-console-next/src" "$d/apps/web-console-next/scripts" "$d/packages/sdk/src"
  echo "packages: [apps/*, packages/*]" > "$d/pnpm-workspace.yaml"
  echo '{"name":"root"}' > "$d/package.json"
  echo "lock: 1" > "$d/pnpm-lock.yaml"
  echo "export const name = 'baseline';" > "$d/apps/web-console-next/src/app.ts"
  echo "export class Client {}" > "$d/packages/sdk/src/index.ts"
  echo "{}" > "$d/apps/web-console-next/wrangler.jsonc"
  cp "$tool" "$d/apps/web-console-next/scripts/console-artifact.mjs"
}
mkbuild() {
  local d="$1"
  mkdir -p "$d/apps/web-console-next/.open-next/assets" "$d/apps/web-console-next/node_modules/.bin"
  # Like OpenNext's output: a require() by absolute build-machine path.
  echo "require('/home/runner/work/x/handler.mjs'); export default {}" > "$d/apps/web-console-next/.open-next/worker.js"
  echo "asset" > "$d/apps/web-console-next/.open-next/assets/a.txt"
  # A stand-in wrangler: `deploy --dry-run --outdir <dir>` writes the bundle,
  # with the absolute require resolved — or not, when BUNDLE_LEAKS is set.
  cat > "$d/apps/web-console-next/node_modules/.bin/wrangler" <<'W'
#!/usr/bin/env bash
while [ $# -gt 0 ]; do [ "$1" = "--outdir" ] && out="$2"; shift; done
mkdir -p "$out"
if [ -n "${BUNDLE_LEAKS:-}" ]; then echo "require('/home/runner/work/x/handler.mjs')" > "$out/worker.js"
else echo "export default { fetch() {} } // bundled" > "$out/worker.js"; fi
W
  chmod +x "$d/apps/web-console-next/node_modules/.bin/wrangler"
}
run() { node "$1/apps/web-console-next/scripts/console-artifact.mjs" "${@:2}"; }

echo "── the source hash"
mkws "$work/base"
h1="$(run "$work/base" hash)"
mkbuild "$work/base"
echo "{}" > "$work/base/apps/web-console-next/tsconfig.tsbuildinfo"
mkdir -p "$work/base/packages/sdk/node_modules/x" && echo y > "$work/base/packages/sdk/node_modules/x/y"
h2="$(run "$work/base" hash)"
[ "$h1" = "$h2" ] && ok "build output, node_modules and tsbuildinfo do not move it" || bad "hash moved after a build: $h1 → $h2"
echo "changed" >> "$work/base/packages/sdk/src/index.ts"
[ "$(run "$work/base" hash)" != "$h1" ] && ok "a package change moves it" || bad "a package change did not move the hash"
sed -i '$d' "$work/base/packages/sdk/src/index.ts"

echo "── pack"
run "$work/base" pack --out "$work/rel" >/dev/null
run "$work/base" pack --out "$work/rel2" >/dev/null
asset="web-console-next-$h1.tar.gz"
[ -f "$work/rel/$asset" ] && [ -f "$work/rel/$asset.sha256" ] && ok "named by the source hash, with a .sha256" || bad "expected $asset"
cmp -s "$work/rel/$asset" "$work/rel2/$asset" && ok "deterministic: the same build packs to the same bytes" || bad "two packs differ"
mkdir -p "$work/peek" && tar -xzf "$work/rel/$asset" -C "$work/peek"
grep -q "bundled" "$work/peek/.open-next/worker.js" && [ -f "$work/peek/.open-next/assets/a.txt" ] \
  && ok "holds the bundled worker and the assets, not OpenNext's raw output" || bad "the artifact is not the bundled worker + assets"
if BUNDLE_LEAKS=1 run "$work/base" pack --out "$work/rel3" >/dev/null 2>&1; then
  bad "packed a worker that still require()s an absolute build-machine path"
else
  ok "refuses a bundle that still require()s an absolute path"
fi

echo "── pin and build in a product"
mkws "$work/prod"
echo "export const name = 'acme';" > "$work/prod/apps/web-console-next/src/app.ts"   # the rebrand
run "$work/prod" pin --baseline "$work/base" --repo o/r --from "file://$work/rel" --root "$work/prod" >/dev/null
pin="$work/prod/apps/web-console-next/console-artifact.pin.json"
[ -f "$pin" ] && grep -q "$asset" "$pin" && ok "pins the baseline's artifact" || bad "no pin written"
out="$(run "$work/prod" build 2>&1)"
[ -f "$work/prod/apps/web-console-next/.open-next/worker.js" ] && grep -q "no build" <<<"$out" && ok "an unchanged product fetches it instead of building" || bad "did not fetch: $out"

echo "export const extra = 1;" >> "$work/prod/apps/web-console-next/src/app.ts"
out="$(run "$work/prod" build 2>&1 || true)"
grep -q "building from source" <<<"$out" && ok "a changed console builds from source" || bad "drift not detected: $out"
sed -i '$d' "$work/prod/apps/web-console-next/src/app.ts"

cp "$work/rel/$asset" "$work/orig"; printf x >> "$work/rel/$asset"
if run "$work/prod" build >/dev/null 2>&1; then bad "a tampered asset was accepted"; else ok "a tampered asset fails the build"; fi
cp "$work/orig" "$work/rel/$asset"

run "$work/prod" pin --baseline "$work/base" --repo o/r --from "file://$work/empty" --root "$work/prod" >/dev/null
[ ! -f "$pin" ] && ok "no artifact, no pin: the product builds as before" || bad "a pin survived a missing artifact"

echo "── the rebrand leaves the pin alone"
grep -q 'console-artifact\\\\.pin\\\\.json' "$root/tooling/rebrand/rebrand.mjs" && ok "rebrand.mjs excludes console-artifact.pin.json" || bad "rebrand.mjs would rewrite the pin's baseline URL"
grep -q 'console-artifact.mjs", "pin"' "$root/repo-blueprint.yaml" && ok "the 05 phase pins it" || bad "repo-blueprint.yaml has no console-artifact pin hook"
grep -q "buildCommand: node scripts/console-artifact.mjs build" "$root/apps/web-console-next/component.yaml" && ok "the component builds through it" || bad "component.yaml does not build through console-artifact.mjs"

[ "$fail" = 0 ] && echo "✓ console-artifact" || { echo "✕ console-artifact" >&2; exit 1; }
