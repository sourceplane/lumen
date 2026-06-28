import type { Env } from "./env.js";
import { route } from "./router.js";

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    return route(request, env);
  },
} satisfies ExportedHandler<Env>;

// perf(db): reverted to per-request DB client (task 0134 connection reuse rolled back).

// orun-ci-probe: dummy change #1 to exercise PR job claim against the new backend (api-edge-prod) — no behavior change.
