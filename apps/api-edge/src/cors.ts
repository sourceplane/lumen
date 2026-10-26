import type { Env } from "./env";
import { CONSOLE_ENVIRONMENTS, consoleWorkersDevOrigins } from "./app-config";

// Deploy hostnames for `apps/web-console-next` (Next.js + opennextjs/cloudflare)
// under the cloudflare-workers-assets-turbo composition. Per-env naming via
// `${prefix}-${env}` so the cutover keeps a stable shape across environments.
// The identity behind those names (subdomain, worker prefix) is resolved per
// request by `./app-config` — from the Worker's `vars`, this tree's constants,
// and the subdomain the edge's own hostname names — so the allowlist tracks
// where the console is actually deployed rather than what the bundle was built
// with. See the header of `./app-config` for why that matters.
//
// Legacy `apps/web-console` (vanilla Vite, Pages) was decommissioned in Task 0083
// (custom-domain swing to web-console-next Workers). No CORS allowlist entry is
// needed for the now-orphaned Pages hostnames — they are not served by any
// current frontend.

const LOCALHOST_RE = /^https?:\/\/localhost(:\d+)?$/;
const VITE_DEV_RE = /^https?:\/\/127\.0\.0\.1(:\d+)?$/;

const ALLOWED_HEADERS = [
  "authorization",
  "content-type",
  "x-request-id",
  "traceparent",
  "idempotency-key",
].join(", ");

const EXPOSED_HEADERS = [
  "x-request-id",
].join(", ");

const ALLOWED_METHODS = "GET, POST, PUT, PATCH, DELETE, OPTIONS";
const MAX_AGE = "86400";

/** The host this Worker is answering on, which names its workers.dev subdomain. */
function requestHost(request: Request): string | null {
  try {
    return new URL(request.url).host;
  } catch {
    return null;
  }
}

export function isAllowedOrigin(origin: string | null, env: Env, host?: string | null): boolean {
  if (!origin) return false;

  if (LOCALHOST_RE.test(origin)) return true;
  if (VITE_DEV_RE.test(origin)) return true;

  const environment = env.ENVIRONMENT;
  const customDomain = env.CONSOLE_CUSTOM_DOMAIN;

  if (customDomain && origin === `https://${customDomain}`) return true;

  // stage and prod each trust their OWN console only: a stage console may not
  // call the prod edge. Everything else (dev, local, tests) trusts all three.
  if (environment === "stage" || environment === "prod") {
    return consoleWorkersDevOrigins(environment, env, host).includes(origin);
  }

  for (const consoleEnvironment of CONSOLE_ENVIRONMENTS) {
    if (consoleWorkersDevOrigins(consoleEnvironment, env, host).includes(origin)) return true;
  }

  return false;
}

export function handlePreflight(request: Request, env: Env): Response | null {
  if (request.method !== "OPTIONS") return null;

  const origin = request.headers.get("origin");
  if (!isAllowedOrigin(origin, env, requestHost(request))) {
    return new Response(null, { status: 204 });
  }

  return new Response(null, {
    status: 204,
    headers: {
      "access-control-allow-origin": origin!,
      "access-control-allow-methods": ALLOWED_METHODS,
      "access-control-allow-headers": ALLOWED_HEADERS,
      "access-control-expose-headers": EXPOSED_HEADERS,
      "access-control-max-age": MAX_AGE,
      "access-control-allow-credentials": "true",
      vary: "Origin",
    },
  });
}

export function applyCorsHeaders(response: Response, request: Request, env: Env): Response {
  const origin = request.headers.get("origin");
  if (!isAllowedOrigin(origin, env, requestHost(request))) return response;

  const headers = new Headers(response.headers);
  headers.set("access-control-allow-origin", origin!);
  headers.set("access-control-allow-credentials", "true");
  headers.set("access-control-expose-headers", EXPOSED_HEADERS);
  headers.set("vary", "Origin");

  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers,
  });
}
