#!/usr/bin/env node
// Park / unpark deployable components (zero-dependency).
//
// The bootstrap model: the FULL tree lands on main in one push, but every
// component that would DEPLOY on a main push starts "parked" — its
// `subscribe.environments` emptied, the original block stashed under
// flows/subscriptions/<name>.yaml — so the first push runs only the offline
// verify fleet. Each bootstrap batch PR then UN-parks its components, and the
// merge's main convergence deploys exactly that batch, in order. (The same
// mechanism the baseline uses to park cloudflare-domain.)
//
// Usage:
//   node flows/common/park.mjs park           # park every deployable component
//   node flows/common/park.mjs unpark <name>… # restore named components
//   node flows/common/park.mjs status         # list parked / live
//
// Verify-only components (turbo-package builds and tests) are never parked —
// they carry no deploy profile, and their lanes are the fleet smoke-check.

import * as fs from "node:fs";
import * as path from "node:path";

const STASH_DIR = "flows/subscriptions";
// Component types whose main-push profileRules deploy/apply/migrate.
const DEPLOYABLE_TYPES = new Set([
  "cloudflare-worker-turbo",
  "cloudflare-workers-assets-turbo",
  "terraform",
  "db-migrate",
]);

function componentFiles() {
  const roots = ["apps", "infra", "packages", "tests"];
  const out = [];
  const walk = (dir) => {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const p = path.join(dir, entry.name);
      if (entry.isDirectory() && entry.name !== "node_modules") walk(p);
      else if (entry.name === "component.yaml") out.push(p);
    }
  };
  for (const r of roots) if (fs.existsSync(r)) walk(r);
  return out.sort();
}

function readMeta(file) {
  const s = fs.readFileSync(file, "utf8");
  const name = (s.match(/^\s{2}name:\s*(\S+)/m) ?? [])[1];
  const type = (s.match(/^\s{2}type:\s*(\S+)/m) ?? [])[1];
  return { s, name, type };
}

// The subscribe block: from the `  subscribe:` line to the next top-level
// spec key (2-space indent) or EOF/comment-tail.
function findSubscribe(s) {
  const start = s.search(/^  subscribe:\s*$/m);
  if (start === -1) return null;
  const rest = s.slice(start);
  const m = rest.slice(1).search(/^  [a-zA-Z]/m);
  const end = m === -1 ? s.length : start + 1 + m;
  return { start, end, block: s.slice(start, end) };
}

const mode = process.argv[2];
if (mode === "park") {
  fs.mkdirSync(STASH_DIR, { recursive: true });
  let parked = 0;
  for (const file of componentFiles()) {
    const { s, name, type } = readMeta(file);
    if (!DEPLOYABLE_TYPES.has(type)) continue;
    const sub = findSubscribe(s);
    if (!sub || /environments:\s*\[\]/.test(sub.block)) continue;
    fs.writeFileSync(path.join(STASH_DIR, `${name}.yaml`), sub.block);
    const replacement =
      "  # PARKED by flows/common/park.mjs — restored per bootstrap batch\n" +
      "  # (flows/bootstrap-flow.yaml); original block in\n" +
      `  # ${STASH_DIR}/${name}.yaml\n` +
      "  subscribe:\n    environments: []\n";
    fs.writeFileSync(file, s.slice(0, sub.start) + replacement + s.slice(sub.end));
    parked++;
    console.log(`parked ${name} (${file})`);
  }
  console.log(`${parked} component(s) parked`);
} else if (mode === "unpark") {
  let names = process.argv.slice(3);
  if (names.length === 0) {
    console.error("unpark: name at least one component (or --all)");
    process.exit(2);
  }
  // `unpark --all`: everything stashed, except components parked by design.
  // cloudflare-domain stays parked until its zone exists in the Cloudflare
  // account (see the restore note in its component.yaml) — the single-run
  // bootstrap must not trip over an absent zone.
  const KEEP_PARKED = new Set(["cloudflare-domain"]);
  if (names.length === 1 && names[0] === "--all") {
    names = fs.existsSync(STASH_DIR)
      ? fs
          .readdirSync(STASH_DIR)
          .filter((f) => f.endsWith(".yaml"))
          .map((f) => f.replace(/\.yaml$/, ""))
          .filter((nm) => !KEEP_PARKED.has(nm))
          .sort()
      : [];
    if (names.length === 0) {
      console.log("unpark --all: nothing stashed (already unparked)");
      process.exit(0);
    }
  }
  for (const nm of names) {
    const stash = path.join(STASH_DIR, `${nm}.yaml`);
    if (!fs.existsSync(stash)) {
      console.error(`unpark: no stashed subscription for ${nm}`);
      process.exit(1);
    }
    const file = componentFiles().find((f) => readMeta(f).name === nm);
    if (!file) {
      console.error(`unpark: no component.yaml with name ${nm}`);
      process.exit(1);
    }
    const { s } = readMeta(file);
    const sub = findSubscribe(s);
    if (!sub) {
      console.error(`unpark: ${nm} has no subscribe block`);
      process.exit(1);
    }
    fs.writeFileSync(file, s.slice(0, sub.start) + fs.readFileSync(stash, "utf8") + s.slice(sub.end));
    fs.unlinkSync(stash);
    console.log(`unparked ${nm}`);
  }
} else if (mode === "status") {
  for (const file of componentFiles()) {
    const { s, name, type } = readMeta(file);
    if (!DEPLOYABLE_TYPES.has(type)) continue;
    const parked = fs.existsSync(path.join(STASH_DIR, `${name}.yaml`));
    console.log(`${parked ? "parked" : "live  "}  ${name}`);
  }
} else {
  console.error("usage: park.mjs park | unpark <name>…|--all | status");
  process.exit(2);
}
