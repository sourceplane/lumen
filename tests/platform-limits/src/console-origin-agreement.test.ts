/**
 * The workers.dev subdomain must be ONE value across the repository.
 *
 * It is the only piece of this product's identity that is an *account* fact:
 * every other name (the repo slug, the product name, the worker prefixes) is
 * known the moment the repository is created, but the Cloudflare account's
 * workers.dev subdomain is only known once the Cloudflare connection is read.
 * The bootstrap therefore writes a PLACEHOLDER first and corrects it later,
 * and each phase only rewrites the files of the component it is building.
 *
 * So a component built before the correction keeps the placeholder, and
 * nothing fails: both halves typecheck, deploy, and answer /health. What
 * breaks is only the cross-origin contract between the console and the
 * fleet — and only in a browser:
 *
 *   - `apps/api-edge` (CORS allowlist) — the console's preflight comes back
 *     without `access-control-allow-origin`, so every call from the console
 *     fails as "Failed to fetch". The login screen shows it first.
 *   - `apps/identity-worker` (`OAUTH_ALLOWED_CONSOLE_ORIGINS`) — the open-
 *     redirect guard refuses the console's own `returnTo`, so OAuth sign-in
 *     dead-ends after the provider hands the user back.
 *
 * Both shipped that way on a product born from this baseline (2026-10-26):
 * the edge named `test-<repo>` while the console was deployed on the real
 * account subdomain. The edge now reads the subdomain off its own hostname
 * too (`apps/api-edge/src/app-config.ts`), which repairs CORS whatever the
 * bundle says — but the identity-worker's allowlist is an open-redirect
 * guard, deliberately literal, and nothing but agreement can save it.
 *
 * Hence this guard: if two places name different subdomains, one of them is
 * a leftover placeholder, and a browser-only failure is already in the
 * repository. Setting the subdomain is one substitution across every file
 * (`node tooling/rebrand/rebrand.mjs --values <file>`), never one component.
 */

import { readFileSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { join } from "node:path";

const REPO_ROOT = join(process.cwd(), "..", "..");

// `<worker>.<subdomain>.workers.dev`, the only shape workers.dev serves.
const WORKERS_DEV_RE = /\b([a-z0-9][a-z0-9-]*)\.([a-z0-9][a-z0-9-]*)\.workers\.dev\b/g;

// Subdomains of OTHER people's accounts, which this product only calls.
const FOREIGN_SUBDOMAINS = new Set([
  "oruncloud", // the Orun control plane (intent.yaml `backendUrl`)
]);

// Where this product's own identity is written: the component trees and the
// deployment intent, runbooks included — a runbook naming a host nobody can
// reach is the same leftover. The top-level `docs/` and `specs/` narrate the
// BASELINE and are left out; they are not this product's configuration.
const SEARCH_PATHS = [
  "apps",
  "packages",
  "infra",
  "tooling",
  "intent.yaml",
  "blueprint.yaml",
];

function trackedFiles(): string[] {
  return execFileSync("git", ["ls-files", "-z", "--", ...SEARCH_PATHS], {
    cwd: REPO_ROOT,
    encoding: "utf-8",
    maxBuffer: 32 * 1024 * 1024,
  })
    .split("\0")
    .filter(Boolean);
}

interface Mention {
  file: string;
  subdomain: string;
  host: string;
}

function mentions(): Mention[] {
  const found: Mention[] = [];
  for (const file of trackedFiles()) {
    let contents: string;
    try {
      contents = readFileSync(join(REPO_ROOT, file), "utf-8");
    } catch {
      continue; // a submodule or a symlink to nowhere; nothing to read
    }
    for (const match of contents.matchAll(WORKERS_DEV_RE)) {
      const subdomain = match[2]!;
      if (FOREIGN_SUBDOMAINS.has(subdomain)) continue;
      found.push({ file, subdomain, host: match[0] });
    }
  }
  return found;
}

describe("workers.dev subdomain agreement", () => {
  const found = mentions();

  it("is named somewhere, so this guard is guarding something", () => {
    expect(found.length).toBeGreaterThan(0);
  });

  it("is the same subdomain everywhere it is named", () => {
    const bySubdomain = new Map<string, string[]>();
    for (const { file, subdomain } of found) {
      const files = bySubdomain.get(subdomain) ?? [];
      if (!files.includes(file)) files.push(file);
      bySubdomain.set(subdomain, files);
    }

    if (bySubdomain.size > 1) {
      const report = [...bySubdomain.entries()]
        .sort((a, b) => b[1].length - a[1].length)
        .map(([subdomain, files]) =>
          `  ${subdomain}.workers.dev\n${files.map((f) => `    ${f}`).join("\n")}`,
        )
        .join("\n");
      throw new Error(
        "This repository names more than one workers.dev subdomain. One of them is a " +
          "leftover bootstrap placeholder, and the console cannot reach the fleet it " +
          "names: CORS and the OAuth return-to guard both compare origins literally.\n" +
          "Set the subdomain across EVERY file at once — " +
          "`node tooling/rebrand/rebrand.mjs --values <file>` — not per component.\n\n" +
          report,
      );
    }

    expect([...bySubdomain.keys()]).toHaveLength(1);
  });
});
