#!/usr/bin/env node
// Clear a landing's own pen branch when an earlier run left one behind
// (zero-dependency).
//
// WHAT THIS FIXES, exactly. `orun.pr/land@v1` lands a phase on the provenance
// pen's branch, `orun/<TASK-KEY>-<branchSlug>`, with a plain `git push -u`.
// If a build STOPS between that push and the merge — the token expires, the
// host goes away, somebody closes the window — the branch and its pull
// request are left on the remote, pointing at a commit of that run's.
//
// A retry re-places the phase and makes a FRESH commit on the same parent.
// The two commits are siblings, not ancestors, so the push is rejected:
//
//     ! [rejected]  orun/BASE-5-04-workers -> orun/BASE-5-04-workers (non-fast-forward)
//     hint: Updates were rejected because the tip of your current branch is
//     hint: behind its remote counterpart.
//
// and it is rejected identically on every retry, for ever. Observed on
// pullely/multi-tenant-saas (2026-10-25): the build stopped after 04-workers'
// PR went green, and every "Retry from 04-workers" after it died on this push
// without reaching a single step of the phase's real work. Git's hint is
// misleading, too — the branches have DIVERGED, so `git pull` is not the fix;
// it would merge the abandoned commit back in and land a doubled diff.
//
// So each landing clears its own branch first. The branch belongs to this
// phase's task: nothing else writes it, and deleting it closes the pull
// request that was going nowhere. The next push creates it fresh.
//
//   node pen-reset.mjs --branch orun/BASE-5-04-workers [--remote origin]
//   node pen-reset.mjs --branch orun/BASE-5-04-workers --check   # report only
//
// A branch whose remote tip is already an ancestor of HEAD is LEFT ALONE: it
// merged, and the push that follows fast-forwards. Only a diverged one is
// deleted, and only under `orun/` — the guard below makes it impossible for a
// mistemplated argument to delete `main`.
//
// Best effort by design: a remote this cannot reach, or a git that refuses
// the delete, is reported and exits 0. The landing is what reports a real
// failure; a cleanup must not be the thing that stops a build.

import { spawnSync } from "node:child_process";

function arg(name, fallback) {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 && process.argv[i + 1] !== undefined ? process.argv[i + 1] : fallback;
}

function git(...args) {
  const r = spawnSync("git", args, { encoding: "utf8" });
  return { ok: r.status === 0, out: (r.stdout ?? "").trim(), err: (r.stderr ?? "").trim() };
}

const branch = arg("branch", "");
const remote = arg("remote", "origin");
const checkOnly = process.argv.includes("--check");

if (!branch) {
  console.error("pen-reset: --branch is required");
  process.exit(2);
}
// The guard. Only the pen's own namespace, and never a ref with a path escape
// or a wildcard in it.
if (!/^orun\/[A-Za-z0-9._-]+$/.test(branch)) {
  console.error(`pen-reset: refusing to touch "${branch}" — only orun/<task>-<slug> pen branches`);
  process.exit(2);
}

const ls = git("ls-remote", "--heads", remote, branch);
if (!ls.ok) {
  console.log(`pen-reset: could not reach ${remote} (${ls.err.split("\n")[0] || "no detail"}); leaving ${branch} alone`);
  process.exit(0);
}
if (ls.out === "") {
  console.log(`pen-reset: no ${branch} on ${remote}; nothing to clear`);
  process.exit(0);
}

const tip = ls.out.split(/\s+/)[0];

// Is the remote tip already in this history? Fetch it by sha-less ref first —
// a shallow or fresh clone may not have the object.
git("fetch", "--quiet", remote, branch);
const reachable = git("merge-base", "--is-ancestor", tip, "HEAD").ok;
if (reachable) {
  console.log(`pen-reset: ${branch} (${tip.slice(0, 8)}) is already in this history; the push will fast-forward`);
  process.exit(0);
}

if (checkOnly) {
  console.log(`pen-reset: ${branch} (${tip.slice(0, 8)}) has diverged — a push would be rejected non-fast-forward`);
  process.exit(1);
}

const del = git("push", remote, "--delete", branch);
if (!del.ok) {
  console.log(
    `pen-reset: ${branch} (${tip.slice(0, 8)}) has diverged but could not be deleted ` +
      `(${del.err.split("\n")[0] || "no detail"}). The landing's push will be rejected; ` +
      `delete it by hand — git push ${remote} --delete ${branch} — and re-run this phase.`,
  );
  process.exit(0);
}
console.log(
  `pen-reset: deleted ${branch} (${tip.slice(0, 8)}) — an earlier run left it behind, ` +
    `and its pull request with it. This landing opens a fresh one.`,
);
