# saas-free-tier — Implementation Status

As-built record. One row per milestone; notes below carry the decisions and the
things that turned out to be untrue.

| Milestone | Status | Notes | PR |
|---|---|---|---|
| FT0 | ✅ Shipped | Profile spec + cron topology + `FREE_TIER` budgets + fleet-wide minify + `tests/platform-limits`. Found and fixed a cursor bug while capping fanout (see notes). | #94 |
| FT1 | 🗓️ Planned | Single-environment deployment, guarded. | — |
| FT2 | 🗓️ Planned | Chain-depth + subrequest audit. | — |
| FT3 | 🗓️ Planned | Request-path cost instrumentation. | — |
| FT4 | 🗓️ Planned | Connection reuse / SCRAM cost. | — |
| FT5 | 🗓️ Planned | Console against the 3MB gzip cap. | — |
| FT6 | ⛔ Gated | Monolith mode. Entry condition is an FT3 measurement. | — |

## Notes

- **2026-08-20: the cron ceiling was arithmetic, not capacity.** The account was
  at 6 triggers against a limit of 5 because a top-level `triggers` block is
  inherited by every named environment — three declarations across stage + prod.
  Moving the declarations into `env.prod` brought it to 3 without dropping a
  single job from prod. The earlier resolution recorded in
  `saas-integrations/IMPLEMENTATION-STATUS.md` — "account upgraded to Workers
  Paid" — is superseded: the upgrade was never the only way out.

- **2026-08-20: a fan-out ticker was considered and rejected.** One cron calling
  the three jobs over service bindings is the obvious way to spend one trigger
  instead of three. It is wrong here: CPU time is summed across a service-binding
  chain, so the ticker and all three jobs would share a single 10 ms budget.
  Durable Object alarms are the shape that scales past 5 jobs, because an alarm
  invocation is its own invocation with its own budget.

- **2026-08-20: capping deliveries surfaced a real bug.** Stopping the dispatcher
  mid-fanout advanced the dispatch cursor past an event whose remaining
  subscriptions had not been delivered — silent, permanent loss for those
  subscribers. Fixed by holding the cursor back on an incomplete fanout. This is
  a correctness fix on the paid plan too; the free-tier budget is only what made
  it reachable.

- **2026-08-20: `MAX_RETRY_BATCH = 100` was never free-plan-viable.** One
  outbound fetch per delivery against a 50-subrequest invocation ceiling means
  the pass is killed mid-flight, not merely slowed. Worth stating plainly because
  "it will just be slower on the free plan" is the intuition the numbers refute.

- **2026-08-20: CI on `main` is red for an unrelated reason, and it gates this
  epic.** Every `*.dev.verify-deploy` lane fails with
  `secret resolution failed: ... Secret not found`. It reproduces on `main` at
  `7b07605` (run 198, 2026-08-06) with no free-tier change in the tree, and the
  last green run was #190. The dev lanes appear to have been latently broken and
  simply not scheduled until PR #93 added `dependsOn` edges for bundled workspace
  packages, which widened `--changed` to mark every worker changed. FT0 widens it
  the same way by touching every wrangler template. The missing secret lives in
  the orun workspace, not the repo, so this is not fixable from a PR.
