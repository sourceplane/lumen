# Epic: saas-free-tier

**Lumen should run on a Cloudflare account with no Workers Paid subscription.**
Not a fork, not a cut-down build — the same workers, the same contracts, the
same jobs, configured *down* until every invocation fits inside the free plan's
ceilings. The profile is the deliverable; `specs/profiles/free-tier.md` is its
contract.

## Status

| Field | Value |
|-------|-------|
| Status | **In progress** — FT0 shipped; FT1–FT5 planned; FT6 gated on FT2/FT3 evidence |
| Cluster | **FT** (deployment profile — sits on top of the Solo profile, `SOLO_MODE`) |
| Owner(s) | `specs/profiles/free-tier.md` · `apps/webhooks-worker` · `apps/integrations-worker` · `apps/metering-worker` · `tests/platform-limits` |
| Target branch | `main` (one PR per milestone) |
| Builds on | `specs/profiles/solo-m0.md` (single org — see *Assumes Solo*), the BF6 deploy-time wiring, and the existing cursor/retry semantics in the scheduled jobs |
| Decisions locked | (1) **Budget, don't disable** — no job is turned off, only how much of its backlog one pass claims changes; (2) **one switch**, `FREE_TIER`, off by default in code so the paid baseline is the safe default; (3) **cron topology is unconditional** — per-environment declaration is better on either plan; (4) a **fan-out ticker is rejected** — one cron calling the jobs over service bindings would put the ticker and all three jobs inside a single 10ms CPU budget. |
| Gate | FT6 (monolith mode) is gated on evidence FT2/FT3 produce. It is not scheduled until the request path's chained CPU cost is known. |

## The one constraint that shapes everything

CPU time is **summed across a service-binding chain and billed as one request**
— *"the total amount of CPU time used across both Worker A and Worker B"*
([Workers pricing][pricing]) — with a hard cap of 32 worker invocations per
request. On the free plan that means

```
api-edge → integrations-worker → policy-worker → membership-worker → billing-worker
```

shares **one 10 ms budget across all five**, including the JSON serialize and
parse at every hop.

Lumen's worker-per-bounded-context architecture is what conflicts with the free
plan. The 5-cron-trigger ceiling that started this epic was only the first
symptom to surface, because it is the only one that fails loudly at deploy time.
Everything else fails as a 1102 at runtime, under load, in production.

So the epic is sequenced around **making that cost visible before trying to fix
it** (FT2, FT3), and only then deciding whether the architecture has to change
for this profile (FT6).

## Milestones

| ID | Milestone | Status |
|----|-----------|--------|
| FT0 | Profile foundation — spec, cron topology, scheduled-pass budgets, minify, limits guard | ✅ Shipped |
| FT1 | Account budget — price the deployed set against every per-account ceiling | ✅ Shipped |
| FT2 | Chain-depth audit — the binding graph bounded, pinned, and its cycles named | ✅ Shipped |
| FT3 | Request-path cost instrumentation — re-scoped: CPU is unmeasurable in-worker; hop count and wall time remain | ⚠️ Re-scoped, not started |
| FT4 | Connection reuse — closed: runtime-forbidden, already tried and reverted | ✅ Closed (no change) |
| FT5 | Console on the free plan — bundle measured, minified and guarded | ✅ Shipped |
| FT6 | Monolith mode — collapse the domain contexts for this profile | ⛔ Gated on Cloudflare CPU telemetry |

Per-milestone detail: [`implementation-plan.md`](./implementation-plan.md).
As-built record: [`IMPLEMENTATION-STATUS.md`](./IMPLEMENTATION-STATUS.md).

[pricing]: https://developers.cloudflare.com/workers/platform/pricing/
