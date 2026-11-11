// Instance identity for api-edge (saas-bootstrap-factory BF3 seam).
//
// Every deployment-identity literal this Worker needs lives here, so a new
// instance of the starter retargets one file (or, later, one generated
// config) instead of hunting through handler code. Do not add behavior —
// values and trivial derivations only.
//
// RUNTIME, NOT BUILD, for the console identity below. The workers.dev
// subdomain is an *account* fact: the bootstrap only learns it once the
// Cloudflare connection is read, which is after the scaffold phase has
// already written this file. A product whose edge was built from the
// scaffold's placeholder therefore shipped a CORS allowlist naming a console
// that does not exist, and every console fetch failed the preflight
// ("Failed to fetch" at the login screen) until the edge happened to be
// rebuilt. So the two values are resolved per request:
//
//   1. the Worker's `vars` (wrangler.template.jsonc), then
//   2. these constants, and — for the subdomain — additionally
//   3. the workers.dev subdomain THIS Worker is answering on.
//
// (3) is what makes the allowlist self-correcting: the edge and the console
// are deployed to one Cloudflare account, so the subdomain in the edge's own
// hostname is the console's subdomain, whatever literal the bundle carries.

/** The Cloudflare account's workers.dev subdomain serving this instance. */
export const WORKERS_DEV_SUBDOMAIN = "rahulvarghesepullely";

/** Worker name prefix of the console delivery (per-env: `${prefix}-${env}`). */
export const CONSOLE_WORKER_PREFIX = "lumen-web-console-next";

/** The environments a console deploy can serve (mirrors the console's own list). */
export const CONSOLE_ENVIRONMENTS = ["dev", "stage", "prod"] as const;

/** Where the console this edge trusts is deployed. */
export interface ConsoleIdentity {
  workersDevSubdomain: string;
  consoleWorkerPrefix: string;
}

/** This tree's own identity: what a deploy with no runtime `vars` serves. */
export const DEFAULT_CONSOLE_IDENTITY: ConsoleIdentity = {
  workersDevSubdomain: WORKERS_DEV_SUBDOMAIN,
  consoleWorkerPrefix: CONSOLE_WORKER_PREFIX,
};

/** The subset of `Env` this seam reads, so it is callable with a bare object. */
export interface ConsoleIdentityEnv {
  CONSOLE_WORKERS_DEV_SUBDOMAIN?: string;
  CONSOLE_WORKER_PREFIX?: string;
}

/** The Worker `vars` that override each field at runtime. */
export const RUNTIME_KEYS: Record<keyof ConsoleIdentity, keyof ConsoleIdentityEnv> = {
  workersDevSubdomain: "CONSOLE_WORKERS_DEV_SUBDOMAIN",
  consoleWorkerPrefix: "CONSOLE_WORKER_PREFIX",
};

function pick(env: ConsoleIdentityEnv, key: keyof ConsoleIdentity): string | undefined {
  const value = env[RUNTIME_KEYS[key]];
  return typeof value === "string" && value.trim() !== "" ? value.trim() : undefined;
}

/**
 * The workers.dev subdomain a host names, for the `<worker>.<subdomain>.workers.dev`
 * shape every workers.dev deploy has. A custom domain names none.
 */
export function workersDevSubdomainFromHost(host: string | null | undefined): string | undefined {
  const labels = (host ?? "").toLowerCase().split(":")[0]!.split(".");
  if (labels.length !== 4) return undefined;
  const [worker, subdomain, workers, dev] = labels;
  if (workers !== "workers" || dev !== "dev") return undefined;
  if (!worker || !subdomain) return undefined;
  return subdomain;
}

/**
 * workers.dev origin of the console for a given environment name, under one
 * console identity. Kept for the single-identity callers and the tests.
 */
export function consoleWorkersDevOrigin(
  environment: string,
  identity: ConsoleIdentity = DEFAULT_CONSOLE_IDENTITY,
): string {
  return `https://${identity.consoleWorkerPrefix}-${environment}.${identity.workersDevSubdomain}.workers.dev`;
}

/**
 * Every workers.dev origin the console for `environment` may answer on: one
 * per subdomain this deploy knows of (the runtime var or the constant, plus
 * the one the edge's own `host` names). Each entry is a complete origin — no
 * wildcard, so an origin that merely *contains* one of them still fails.
 */
export function consoleWorkersDevOrigins(
  environment: string,
  env: ConsoleIdentityEnv = {},
  host?: string | null,
): string[] {
  const consoleWorkerPrefix =
    pick(env, "consoleWorkerPrefix") ?? DEFAULT_CONSOLE_IDENTITY.consoleWorkerPrefix;
  const subdomains = [
    pick(env, "workersDevSubdomain") ?? DEFAULT_CONSOLE_IDENTITY.workersDevSubdomain,
    workersDevSubdomainFromHost(host),
  ];
  const origins: string[] = [];
  for (const workersDevSubdomain of subdomains) {
    if (!workersDevSubdomain) continue;
    const origin = consoleWorkersDevOrigin(environment, {
      workersDevSubdomain,
      consoleWorkerPrefix,
    });
    if (!origins.includes(origin)) origins.push(origin);
  }
  return origins;
}
