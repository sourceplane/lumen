import { handlePreflight, applyCorsHeaders, isAllowedOrigin } from "@api-edge/cors";
import {
  CONSOLE_WORKER_PREFIX,
  WORKERS_DEV_SUBDOMAIN,
  consoleWorkersDevOrigin,
  consoleWorkersDevOrigins,
  workersDevSubdomainFromHost,
} from "@api-edge/app-config";
import type { Env } from "@api-edge/env";

const stageEnv: Env = { ENVIRONMENT: "stage", CONSOLE_CUSTOM_DOMAIN: "stage.lumen.app" };
const prodEnv: Env = { ENVIRONMENT: "prod", CONSOLE_CUSTOM_DOMAIN: "prod.lumen.app" };
const testEnv: Env = { ENVIRONMENT: "test" };

// Post Task 0083: legacy `apps/web-console` (Pages) was decommissioned. The CORS
// allowlist now permits only the custom-domain hostnames + the web-console-next
// `*.workers.dev` shadow hostnames. Origins are built from the same BF3
// identity seam the worker uses (`app-config`), so the assertions exercise the
// allowlist *logic*, not a copy of the literals.
const STAGE_WORKER_ORIGIN = consoleWorkersDevOrigin("stage");
const PROD_WORKER_ORIGIN = consoleWorkersDevOrigin("prod");
const DEV_WORKER_ORIGIN = consoleWorkersDevOrigin("dev");

describe("api-edge cors", () => {
  describe("isAllowedOrigin — stage environment", () => {
    it("allows the stage custom domain origin", () => {
      expect(isAllowedOrigin("https://stage.lumen.app", stageEnv)).toBe(true);
    });

    it("allows the stage workers.dev origin", () => {
      expect(isAllowedOrigin(STAGE_WORKER_ORIGIN, stageEnv)).toBe(true);
    });

    it("rejects the prod custom domain origin", () => {
      expect(isAllowedOrigin("https://prod.lumen.app", stageEnv)).toBe(false);
    });

    it("rejects the prod workers.dev origin", () => {
      expect(isAllowedOrigin(PROD_WORKER_ORIGIN, stageEnv)).toBe(false);
    });

    it("rejects the legacy Pages console origins", () => {
      expect(isAllowedOrigin("https://lumen-web-console.pages.dev", stageEnv)).toBe(false);
      expect(isAllowedOrigin("https://lumen-web-console-stage.pages.dev", stageEnv)).toBe(false);
      expect(isAllowedOrigin("https://lumen-web-console-prod.pages.dev", stageEnv)).toBe(false);
      expect(isAllowedOrigin("https://abc123.lumen-web-console-stage.pages.dev", stageEnv)).toBe(false);
    });

    it("allows localhost origins", () => {
      expect(isAllowedOrigin("http://localhost:5173", stageEnv)).toBe(true);
      expect(isAllowedOrigin("http://localhost:3000", stageEnv)).toBe(true);
      expect(isAllowedOrigin("https://localhost", stageEnv)).toBe(true);
    });

    it("allows 127.0.0.1 origins", () => {
      expect(isAllowedOrigin("http://127.0.0.1:5173", stageEnv)).toBe(true);
    });
  });

  describe("isAllowedOrigin — prod environment", () => {
    it("allows the prod custom domain origin", () => {
      expect(isAllowedOrigin("https://prod.lumen.app", prodEnv)).toBe(true);
    });

    it("allows the prod workers.dev origin", () => {
      expect(isAllowedOrigin(PROD_WORKER_ORIGIN, prodEnv)).toBe(true);
    });

    it("rejects the stage custom domain origin", () => {
      expect(isAllowedOrigin("https://stage.lumen.app", prodEnv)).toBe(false);
    });

    it("rejects the stage workers.dev origin", () => {
      expect(isAllowedOrigin(STAGE_WORKER_ORIGIN, prodEnv)).toBe(false);
    });

    it("rejects the legacy Pages console origins", () => {
      expect(isAllowedOrigin("https://lumen-web-console.pages.dev", prodEnv)).toBe(false);
      expect(isAllowedOrigin("https://lumen-web-console-prod.pages.dev", prodEnv)).toBe(false);
      expect(isAllowedOrigin("https://feat-branch-42.lumen-web-console-stage.pages.dev", prodEnv)).toBe(false);
    });

    it("allows localhost origins", () => {
      expect(isAllowedOrigin("http://localhost:5173", prodEnv)).toBe(true);
    });

    it("allows 127.0.0.1 origins", () => {
      expect(isAllowedOrigin("http://127.0.0.1:5173", prodEnv)).toBe(true);
    });
  });

  describe("isAllowedOrigin — fallback (test/unknown environment)", () => {
    it("rejects custom domain origins when CONSOLE_CUSTOM_DOMAIN is not set", () => {
      expect(isAllowedOrigin("https://stage.lumen.app", testEnv)).toBe(false);
      expect(isAllowedOrigin("https://prod.lumen.app", testEnv)).toBe(false);
    });

    it("allows custom domain origin when CONSOLE_CUSTOM_DOMAIN is set", () => {
      const envWithDomain: Env = { ENVIRONMENT: "test", CONSOLE_CUSTOM_DOMAIN: "custom.example.com" };
      expect(isAllowedOrigin("https://custom.example.com", envWithDomain)).toBe(true);
    });

    it("allows all workers.dev origins (dev, stage, prod) in fallback env", () => {
      expect(isAllowedOrigin(DEV_WORKER_ORIGIN, testEnv)).toBe(true);
      expect(isAllowedOrigin(STAGE_WORKER_ORIGIN, testEnv)).toBe(true);
      expect(isAllowedOrigin(PROD_WORKER_ORIGIN, testEnv)).toBe(true);
    });

    it("rejects legacy Pages console origins in fallback env", () => {
      expect(isAllowedOrigin("https://lumen-web-console-stage.pages.dev", testEnv)).toBe(false);
      expect(isAllowedOrigin("https://lumen-web-console-prod.pages.dev", testEnv)).toBe(false);
    });

    it("allows localhost origins", () => {
      expect(isAllowedOrigin("http://localhost:5173", testEnv)).toBe(true);
    });
  });

  describe("isAllowedOrigin — common rejections", () => {
    it("rejects null origin", () => {
      expect(isAllowedOrigin(null, stageEnv)).toBe(false);
      expect(isAllowedOrigin(null, prodEnv)).toBe(false);
    });

    it("rejects arbitrary origins", () => {
      expect(isAllowedOrigin("https://evil.com", stageEnv)).toBe(false);
      expect(isAllowedOrigin("https://evil.com", prodEnv)).toBe(false);
      expect(
        // Suffix attack: the real stage origin with `.evil.com` appended must
        // stay disallowed. Derived from the seam so the attack string tracks
        // the real hostname.
        isAllowedOrigin(`${consoleWorkersDevOrigin("stage")}.evil.com`, stageEnv),
      ).toBe(false);
    });

    it("rejects similar but not matching origins", () => {
      expect(isAllowedOrigin("https://other-project.workers.dev", stageEnv)).toBe(false);
      expect(isAllowedOrigin(`${STAGE_WORKER_ORIGIN}:8080`, stageEnv)).toBe(false);
    });
  });

  describe("handlePreflight", () => {
    it("returns null for non-OPTIONS requests", () => {
      const req = new Request("https://api.test/v1/auth/session", { method: "GET" });
      expect(handlePreflight(req, stageEnv)).toBeNull();
    });

    it("returns 204 with CORS headers for allowed stage custom domain", () => {
      const req = new Request("https://api.test/v1/auth/session", {
        method: "OPTIONS",
        headers: { origin: "https://stage.lumen.app" },
      });
      const res = handlePreflight(req, stageEnv);
      expect(res).not.toBeNull();
      expect(res!.status).toBe(204);
      expect(res!.headers.get("access-control-allow-origin")).toBe(
        "https://stage.lumen.app",
      );
      expect(res!.headers.get("access-control-allow-credentials")).toBe("true");
    });

    it("returns 204 with CORS headers for allowed stage workers.dev origin", () => {
      const req = new Request("https://api.test/v1/auth/session", {
        method: "OPTIONS",
        headers: { origin: STAGE_WORKER_ORIGIN },
      });
      const res = handlePreflight(req, stageEnv);
      expect(res).not.toBeNull();
      expect(res!.status).toBe(204);
      expect(res!.headers.get("access-control-allow-origin")).toBe(STAGE_WORKER_ORIGIN);
      expect(res!.headers.get("access-control-allow-methods")).toContain("GET");
      expect(res!.headers.get("access-control-allow-methods")).toContain("POST");
      expect(res!.headers.get("access-control-allow-headers")).toContain("authorization");
      expect(res!.headers.get("access-control-allow-headers")).toContain("content-type");
      expect(res!.headers.get("access-control-allow-headers")).toContain("x-request-id");
      expect(res!.headers.get("access-control-allow-headers")).toContain("traceparent");
      expect(res!.headers.get("access-control-allow-headers")).toContain("idempotency-key");
      expect(res!.headers.get("access-control-allow-credentials")).toBe("true");
      expect(res!.headers.get("vary")).toBe("Origin");
    });

    it("returns 204 without CORS headers when prod custom domain hits stage API", () => {
      const req = new Request("https://api.test/v1/auth/session", {
        method: "OPTIONS",
        headers: { origin: "https://prod.lumen.app" },
      });
      const res = handlePreflight(req, stageEnv);
      expect(res).not.toBeNull();
      expect(res!.status).toBe(204);
      expect(res!.headers.get("access-control-allow-origin")).toBeNull();
    });

    it("returns 204 without CORS headers when prod workers.dev hits stage API", () => {
      const req = new Request("https://api.test/v1/auth/session", {
        method: "OPTIONS",
        headers: { origin: PROD_WORKER_ORIGIN },
      });
      const res = handlePreflight(req, stageEnv);
      expect(res).not.toBeNull();
      expect(res!.status).toBe(204);
      expect(res!.headers.get("access-control-allow-origin")).toBeNull();
    });

    it("returns 204 without CORS headers for disallowed origin", () => {
      const req = new Request("https://api.test/v1/auth/session", {
        method: "OPTIONS",
        headers: { origin: "https://evil.com" },
      });
      const res = handlePreflight(req, stageEnv);
      expect(res).not.toBeNull();
      expect(res!.status).toBe(204);
      expect(res!.headers.get("access-control-allow-origin")).toBeNull();
    });

    it("returns 204 without CORS headers when no origin", () => {
      const req = new Request("https://api.test/v1/auth/session", {
        method: "OPTIONS",
      });
      const res = handlePreflight(req, prodEnv);
      expect(res).not.toBeNull();
      expect(res!.status).toBe(204);
      expect(res!.headers.get("access-control-allow-origin")).toBeNull();
    });
  });

  describe("applyCorsHeaders", () => {
    it("adds CORS headers for stage custom domain on stage env", () => {
      const req = new Request("https://api.test/v1/auth/session", {
        headers: { origin: "https://stage.lumen.app" },
      });
      const original = Response.json({ data: {} }, { status: 200 });
      const res = applyCorsHeaders(original, req, stageEnv);

      expect(res.status).toBe(200);
      expect(res.headers.get("access-control-allow-origin")).toBe(
        "https://stage.lumen.app",
      );
      expect(res.headers.get("access-control-allow-credentials")).toBe("true");
      expect(res.headers.get("vary")).toBe("Origin");
    });

    it("adds CORS headers for allowed stage workers.dev origin on stage env", () => {
      const req = new Request("https://api.test/v1/auth/session", {
        headers: { origin: STAGE_WORKER_ORIGIN },
      });
      const original = Response.json({ data: {} }, { status: 200 });
      const res = applyCorsHeaders(original, req, stageEnv);

      expect(res.status).toBe(200);
      expect(res.headers.get("access-control-allow-origin")).toBe(STAGE_WORKER_ORIGIN);
      expect(res.headers.get("access-control-allow-credentials")).toBe("true");
      expect(res.headers.get("vary")).toBe("Origin");
    });

    it("does not add CORS headers for prod custom domain on stage env", () => {
      const req = new Request("https://api.test/v1/auth/session", {
        headers: { origin: "https://prod.lumen.app" },
      });
      const original = Response.json({ data: {} }, { status: 200 });
      const res = applyCorsHeaders(original, req, stageEnv);

      expect(res.headers.get("access-control-allow-origin")).toBeNull();
    });

    it("does not add CORS headers for prod workers.dev origin on stage env", () => {
      const req = new Request("https://api.test/v1/auth/session", {
        headers: { origin: PROD_WORKER_ORIGIN },
      });
      const original = Response.json({ data: {} }, { status: 200 });
      const res = applyCorsHeaders(original, req, stageEnv);

      expect(res.headers.get("access-control-allow-origin")).toBeNull();
    });

    it("does not add CORS headers for stage custom domain on prod env", () => {
      const req = new Request("https://api.test/v1/auth/session", {
        headers: { origin: "https://stage.lumen.app" },
      });
      const original = Response.json({ data: {} }, { status: 200 });
      const res = applyCorsHeaders(original, req, prodEnv);

      expect(res.headers.get("access-control-allow-origin")).toBeNull();
    });

    it("does not add CORS headers for stage workers.dev origin on prod env", () => {
      const req = new Request("https://api.test/v1/auth/session", {
        headers: { origin: STAGE_WORKER_ORIGIN },
      });
      const original = Response.json({ data: {} }, { status: 200 });
      const res = applyCorsHeaders(original, req, prodEnv);

      expect(res.headers.get("access-control-allow-origin")).toBeNull();
    });

    it("does not add CORS headers for disallowed origin", () => {
      const req = new Request("https://api.test/v1/auth/session", {
        headers: { origin: "https://evil.com" },
      });
      const original = Response.json({ data: {} }, { status: 200 });
      const res = applyCorsHeaders(original, req, stageEnv);

      expect(res.headers.get("access-control-allow-origin")).toBeNull();
    });

    it("preserves original response status and body", async () => {
      const req = new Request("https://api.test/v1/auth/session", {
        headers: { origin: "http://localhost:5173" },
      });
      const body = { error: { code: "unauthenticated", message: "No token" } };
      const original = Response.json(body, { status: 401 });
      const res = applyCorsHeaders(original, req, stageEnv);

      expect(res.status).toBe(401);
      const json = await res.json();
      expect(json).toEqual(body);
      expect(res.headers.get("access-control-allow-origin")).toBe("http://localhost:5173");
    });
  });

  // ── The console identity is a DEPLOY fact, not a build fact ──────────────
  //
  // Regression: a product's edge was built during the scaffold phase, before
  // the bootstrap had read the Cloudflare connection, so its bundle carried a
  // placeholder workers.dev subdomain. The console deployed to the account's
  // real subdomain, every preflight from it came back without
  // `access-control-allow-origin`, and the login screen showed "Failed to
  // fetch" against a perfectly healthy API. The allowlist now reads the
  // subdomain off the edge's OWN hostname as well, so a stale bundle still
  // trusts the console it is deployed beside.
  describe("console identity resolved per deploy", () => {
    // Derived from the seam, never written out: the rebrand rewrites every
    // baseline identity literal in this file, so a hard-coded "live" subdomain
    // would collapse onto the constant in a fork and stop testing anything.
    const LIVE_SUBDOMAIN = `${WORKERS_DEV_SUBDOMAIN}-elsewhere`;
    const RENAMED_CONSOLE_PREFIX = `${CONSOLE_WORKER_PREFIX}-renamed`;
    const edgeHost = (environment: string) => `api-${environment}.${LIVE_SUBDOMAIN}.workers.dev`;
    const consoleOrigin = (environment: string, prefix = CONSOLE_WORKER_PREFIX) =>
      `https://${prefix}-${environment}.${LIVE_SUBDOMAIN}.workers.dev`;

    describe("workersDevSubdomainFromHost", () => {
      it("reads the subdomain out of a workers.dev host", () => {
        expect(workersDevSubdomainFromHost(edgeHost("stage"))).toBe(LIVE_SUBDOMAIN);
      });

      it("ignores a port", () => {
        expect(workersDevSubdomainFromHost(`${edgeHost("stage")}:8787`)).toBe(LIVE_SUBDOMAIN);
      });

      it("names no subdomain for a custom domain or a malformed host", () => {
        // A custom domain, i.e. not `<worker>.<subdomain>.workers.dev`.
        expect(workersDevSubdomainFromHost("api.example.net")).toBeUndefined();
        expect(workersDevSubdomainFromHost("no-subdomain.workers.dev")).toBeUndefined();
        expect(workersDevSubdomainFromHost("a.b.c.workers.dev")).toBeUndefined();
        expect(workersDevSubdomainFromHost("evil.com")).toBeUndefined();
        expect(workersDevSubdomainFromHost(null)).toBeUndefined();
        expect(workersDevSubdomainFromHost(undefined)).toBeUndefined();
      });
    });

    it("allows the console on the subdomain the edge itself answers on", () => {
      // The bundle's constant still says the baseline's subdomain.
      expect(isAllowedOrigin(consoleOrigin("stage"), stageEnv)).toBe(false);
      expect(isAllowedOrigin(consoleOrigin("stage"), stageEnv, edgeHost("stage"))).toBe(true);
    });

    it("still allows the console named by the bundle's own constant", () => {
      expect(isAllowedOrigin(STAGE_WORKER_ORIGIN, stageEnv, edgeHost("stage"))).toBe(true);
    });

    it("allows the console named by the runtime vars", () => {
      const env: Env = {
        ENVIRONMENT: "stage",
        CONSOLE_WORKERS_DEV_SUBDOMAIN: LIVE_SUBDOMAIN,
        CONSOLE_WORKER_PREFIX: RENAMED_CONSOLE_PREFIX,
      };
      const origin = consoleOrigin("stage", RENAMED_CONSOLE_PREFIX);
      expect(isAllowedOrigin(origin, env)).toBe(true);
      // The prefix var applies to the host-derived subdomain too, which is how
      // a console renamed after the edge was built is still trusted.
      expect(
        isAllowedOrigin(
          origin,
          { ENVIRONMENT: "stage", CONSOLE_WORKER_PREFIX: RENAMED_CONSOLE_PREFIX },
          edgeHost("stage"),
        ),
      ).toBe(true);
    });

    it("treats a blank var as unset", () => {
      const env: Env = {
        ENVIRONMENT: "stage",
        CONSOLE_WORKERS_DEV_SUBDOMAIN: "   ",
        CONSOLE_WORKER_PREFIX: "",
      };
      expect(isAllowedOrigin(STAGE_WORKER_ORIGIN, env)).toBe(true);
    });

    it("keeps stage and prod apart on the derived subdomain", () => {
      expect(isAllowedOrigin(consoleOrigin("prod"), stageEnv, edgeHost("stage"))).toBe(false);
      expect(isAllowedOrigin(consoleOrigin("stage"), prodEnv, edgeHost("prod"))).toBe(false);
      expect(isAllowedOrigin(consoleOrigin("prod"), prodEnv, edgeHost("prod"))).toBe(true);
    });

    it("widens to one origin only — no wildcard on the derived subdomain", () => {
      expect(isAllowedOrigin(`${consoleOrigin("stage")}.evil.com`, stageEnv, edgeHost("stage"))).toBe(false);
      expect(isAllowedOrigin(`https://evil.${LIVE_SUBDOMAIN}.workers.dev`, stageEnv, edgeHost("stage"))).toBe(false);
      expect(isAllowedOrigin(`https://${LIVE_SUBDOMAIN}.workers.dev`, stageEnv, edgeHost("stage"))).toBe(false);
      expect(isAllowedOrigin(`${consoleOrigin("stage")}:8080`, stageEnv, edgeHost("stage"))).toBe(false);
      expect(isAllowedOrigin(consoleOrigin("stage").replace("https://", "http://"), stageEnv, edgeHost("stage"))).toBe(false);
    });

    it("derives nothing from a custom-domain edge host", () => {
      expect(isAllowedOrigin(consoleOrigin("stage"), stageEnv, "api.example.net")).toBe(false);
      // …and the custom-domain console is still trusted there.
      expect(isAllowedOrigin("https://stage.lumen.app", stageEnv, "api.example.net")).toBe(true);
    });

    it("offers both subdomains, deduped, and only those", () => {
      expect(consoleWorkersDevOrigins("stage", stageEnv, edgeHost("stage"))).toEqual([
        STAGE_WORKER_ORIGIN,
        consoleOrigin("stage"),
      ]);
      expect(consoleWorkersDevOrigins("stage", { CONSOLE_WORKERS_DEV_SUBDOMAIN: LIVE_SUBDOMAIN }, edgeHost("stage"))).toEqual([
        consoleOrigin("stage"),
      ]);
      expect(consoleWorkersDevOrigins("stage")).toEqual([STAGE_WORKER_ORIGIN]);
    });

    it("preflights the live console origin through the deployed edge host", () => {
      const req = new Request(`https://${edgeHost("stage")}/v1/auth/login/start`, {
        method: "OPTIONS",
        headers: { origin: consoleOrigin("stage") },
      });
      const res = handlePreflight(req, stageEnv);
      expect(res!.status).toBe(204);
      expect(res!.headers.get("access-control-allow-origin")).toBe(consoleOrigin("stage"));
      expect(res!.headers.get("access-control-allow-credentials")).toBe("true");
    });

    it("answers the live console origin with CORS headers on a real response", () => {
      const req = new Request(`https://${edgeHost("stage")}/v1/auth/login/start`, {
        method: "POST",
        headers: { origin: consoleOrigin("stage") },
      });
      const res = applyCorsHeaders(Response.json({ data: {} }), req, stageEnv);
      expect(res.headers.get("access-control-allow-origin")).toBe(consoleOrigin("stage"));
    });
  });
});
