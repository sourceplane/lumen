# saas-free-tier — Implementation Plan

One milestone per PR. Each names its own verification, because most of what this
epic defends cannot be observed from a green test suite: the limits are
per-account, per-invocation, and only bite in production.

---

## FT0 — Profile foundation ✅ Shipped

Establish the profile and remove the ceilings that configuration alone can
remove.

**Delivered**

- `specs/profiles/free-tier.md` — the profile contract, indexed from
  `specs/README.md` and cross-linked with `solo-m0.md`.
- Cron triggers declared per-environment (`env.prod` only) instead of at the top
  level, where wrangler inherits them into every named environment. 6 triggers
  → 3 of the free plan's 5.
- `FREE_TIER` switch, off by default in code, shrinking the webhook dispatch and
  retry batches and the integrations drain batch to fit a 10 ms / 50-subrequest
  invocation.
- A partially fanned-out event no longer advances the dispatch cursor — found
  while capping deliveries mid-fanout, and a correctness fix on either plan.
- `minify: true` fleet-wide, against the 3MB gzip cap.
- `tests/platform-limits` — structural CI guard on the account-wide budget.

**Verified** — fleet typecheck; new suites green; each scheduled worker rendered
from its wiring fixture and dry-run deployed, confirming wrangler accepts an
env-scoped `triggers` block.

---

## FT1 — Single-environment deployment

The profile says "free tier deploys one environment" but nothing enforces it;
today it is only implied by where the crons happen to live. A second environment
silently doubles every per-account cost — cron triggers, worker count,
Hyperdrive configs — and the operator finds out at deploy time.

**Scope**

- A documented deployment recipe for a single-environment free-tier instance:
  which environments a free-tier operator subscribes, and what they give up.
- Extend `tests/platform-limits` from "crons only in prod" to a whole-account
  budget model: given the set of environments a profile deploys, assert every
  per-account limit (crons, worker count, Hyperdrive configs) is inside the free
  plan's allowance.
- Record the two spare cron slots as a budget with an owner, not as slack.

**Verification** — the guard fails when a second environment is added to the
deployed set. Prove it by adding one.

**Independent of** everything else. Cheapest real milestone; do it first.

---

## FT2 — Chain-depth and subrequest audit

The free plan allows 50 subrequests per invocation and 32 worker invocations per
request. Every service-binding hop spends one of each. Nothing in the repo knows
how deep any route's chain is, so nothing can tell you when a new binding pushes
a route over.

**Scope**

- Build the call graph statically: the service bindings in each worker's
  wrangler config give the edges; the facade route matchers in `api-edge/src/*-facade.ts`
  give the entry points.
- Assert the maximum chain depth for any route is inside the free plan's ceiling,
  with headroom for the DB round trips each hop also spends.
- Emit the depth per route so the number is reviewable in the diff, not just
  asserted — the same reasoning as naming the crons in FT0's guard rather than
  counting them.

**Verification** — the guard fails when a binding is added that deepens a chain
past the budget.

**Why before FT6** — this is the cheapest available proxy for the chained-CPU
question. A route that is 5 hops deep is not necessarily over 10 ms, but the
depth is what makes the CPU cost unknowable, and it is measurable from the repo
alone.

---

## FT3 — Request-path cost instrumentation

The chained-CPU question needs numbers. Cloudflare's own CPU metrics are a
dashboard feature; a free-tier operator, by definition, is the person least
likely to have the paid account those numbers come from. The measurement has to
live in the product.

**Scope**

- Extend the existing edge timing seam (`apps/api-edge/src/http.ts` →
  `withTimings`, covered by `tests/api-edge/src/edge-timing.test.ts`) to
  attribute cost per hop rather than per request.
- Make the per-hop breakdown readable from a response header or a single
  structured log line, behind the profile switch or a debug flag — not on by
  default in a hot path.
- Document the reading in the profile spec: what number means "this route will
  not survive the free plan".

**Verification** — a test asserting the breakdown attributes cost to each hop of
a multi-hop facade call.

**Note** — wall-clock is not CPU time, and the instrumentation must say so
rather than implying a precision it does not have. It bounds the answer; it does
not produce it.

---

## FT4 — Connection reuse and the SCRAM cost

`packages/db` uses `postgres.js`, and both scheduled workers carry
`perf(db): reverted to per-request DB client (task 0134 connection reuse rolled back)`.
A fresh Postgres connection performs SCRAM-SHA-256 auth — PBKDF2 at the server's
iteration count, 4096 by default — in the worker, on every request.

Invisible under a 30-second budget. Under 10 ms it is a candidate for the
single largest line item on the request path, and unlike the architecture, it is
cheap to change.

**Scope**

- Measure it with FT3 before changing anything.
- If it is material: restore connection reuse behind the profile, and record why
  task 0134 was rolled back before repeating it. **Read that history first** —
  the rollback presumably had a reason, and this milestone is not a licence to
  re-land a known-bad change.

**Verification** — the FT3 breakdown, before and after, on the same route.

**Gated on FT3** for the measurement, not for the analysis.

---

## FT5 — Console on the free plan

The domain workers gzip to 27–40 KiB against a 3MB cap — a non-issue. The
OpenNext console is the one bundle in the fleet whose size is not obviously
fine, and it is also the one worker whose config (`apps/web-console-next/wrangler.jsonc`)
sets no `minify`, because OpenNext owns its own build.

**Scope**

- Measure the built console worker against the 3MB gzip ceiling.
- Add it to the `tests/platform-limits` size guard if it can be measured without
  a full build in the verify lane; otherwise assert it in the console's own
  build lane, where the artifact already exists.
- Confirm the request accounting: requests to static assets are free and
  unlimited, so the console's real cost against the 100k/day budget is its
  server-rendered routes only. Document the distinction — it is the difference
  between "the console is unaffordable" and "the console is nearly free".

**Independent of** FT2–FT4.

---

## FT6 — Monolith mode ⛔ Gated

If FT2 and FT3 show the request path does not fit in 10 ms of chained CPU, no
amount of configuration saves this profile, and the architecture has to change
*for this profile only*: bundle the domain contexts into one worker and dispatch
in-process, removing the per-hop serialize/parse entirely.

**Not scheduled.** It is a structural change that would earn its own spec, and
committing to it before the measurement exists would be building on a guess.
The bounded contexts stay non-negotiable as *code* boundaries either way — this
is about deployment count, which `specs/roadmap.md` already names as negotiable.

**Entry condition** — an FT3 measurement, on a real deployment, showing the
chained cost of a representative multi-hop route.
