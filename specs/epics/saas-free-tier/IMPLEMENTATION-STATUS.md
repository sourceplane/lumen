# saas-free-tier — Implementation Status

As-built record. One row per milestone; notes below carry the decisions and the
things that turned out to be untrue.

| Milestone | Status | Notes | PR |
|---|---|---|---|
| FT0 | ✅ Shipped | Profile spec + cron topology + `FREE_TIER` budgets + fleet-wide minify + `tests/platform-limits`. Found and fixed a cursor bug while capping fanout (see notes). | #94 |
| FT1 | ✅ Shipped | Account budget priced from the deployed set. Corrected the premise: the profile does not need a single environment. | #99 |
| FT2 | ✅ Shipped | Binding graph bounded at 8 invocations and pinned; 2 cycles named and allowlisted. | #100 |
| FT3 | ⚠️ Re-scoped | CPU is unmeasurable inside a Worker by design; hop count and wall time remain implementable. | #101 |
| FT4 | 🗓️ Planned | Connection reuse / SCRAM cost. | — |
| FT5 | ✅ Shipped | 2296 → 1880 KiB via minify; 61% of the cap, guarded at 2400 KiB in the console's build lane. | #102 |
| FT6 | ⛔ Gated | Monolith mode. Entry condition is Cloudflare CPU telemetry — not FT3, which cannot produce it. | — |

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

- **2026-08-21: RESOLVED — the missing secret was the whole outage, and its
  cause was upstream of Cloudflare entirely.** The Supabase integration
  connection behind `SUPABASE_ACCESS_TOKEN` and `SUPABASE_ORG_ID` had been
  revoked, orphaning both brokered secrets. `supabase` could not apply, so it
  never published `SUPABASE_PROJECT_REF` / `SUPABASE_DB_PASSWORD`;
  `cloudflare-hyperdrive` depends on those and so never published
  `WIRING_CLOUDFLARE_HYPERDRIVE`; and twelve components hard-required that
  document. `WIRING_CLOUDFLARE_KV` was the control that isolated it —
  `cloudflare-kv` has no Supabase dependency and its document was present
  throughout.

  Recovery: both brokered secrets repointed to the live connection (revoke +
  recreate; an in-place `integrations … secret create` against an existing key
  returns a backend 500), then one `# ci:` trailer PR per infra component —
  #95 `supabase`, #96 `cloudflare-hyperdrive`, #97 `db-migrate`. One PR per
  component was necessary, not fastidious: `orun plan --changed` schedules
  directly-changed components only, and the "Dependents" that
  `orun component --changed` prints are dropped at plan time as
  `component not selected`.

  The earlier claim above that this is "not fixable from a PR" was wrong in
  spirit: the *secret* is workspace state, but the applies that publish it are
  driven from the repo, so PRs were exactly the instrument.

- **2026-08-21: FT0 landed and the cron fix was proven on a real deploy.**
  Run 208 deployed all 13 workers to stage and prod, green, with no
  `5 cron triggers per account` error. Worth stating explicitly because the
  verify lanes cannot prove this: `wrangler deploy --dry-run` does not attach
  triggers, so only the deploy profile exercises the ceiling.

- **2026-08-21: secret scoping (the latent fragility, fixed separately).** The
  outage was a missing secret; what turned it into a *fleet-wide* outage was
  the component-level `secretEnv` form. Wiring refs are now declared
  per-environment on `stage` and `prod`, which removed 26 required references
  from 12 dev jobs (verified against `orun plan`). Established empirically
  while choosing the fix: per-environment `secretEnv` is honoured and scopes
  correctly, but per-environment `optionalSecretEnv` is **silently dropped** —
  no error, no warning. Both shapes are now guarded in `tests/platform-limits`.

- **2026-08-21: FT1 landed, and disproved its own premise.** The milestone was
  specified as "make 'free tier deploys one environment' explicit and guarded".
  Measuring the deployed set showed that claim was never true: stage + prod
  cost 3 of 5 cron triggers, 28 of 100 worker scripts and 2 of 10 Hyperdrive
  configs. What must be concentrated in one environment is the *crons* — a
  trigger is charged per deployed environment — and nothing else in the fleet
  is near its ceiling.

  So the guard prices the deployed set instead of enforcing a shape it turned
  out not to need. It applies wrangler's inheritance rule directly, which means
  it charges a top-level `triggers` block to every deployed environment and
  reports the fourth charge by name. The pricing function is unit-tested on
  synthetic configs, so the guard proves it can catch the 6-trigger case
  without a violation being planted in a real file.

- **2026-08-21: FT2 measured the chain, and the number was worse than the spec's
  example.** The chained-CPU section illustrated the problem with a five-worker
  path. Measured from the prod service bindings, the deepest simple chain is
  **8 worker invocations** from `api-edge` — still far inside the platform's
  32-invocation cap, but eight workers sharing one 10ms CPU budget is a
  materially different claim from five. The spec now carries the measured
  figure.

  The audit also surfaced **two cycles**:
  `billing-worker → membership-worker → billing-worker` and
  `membership-worker → notifications-worker → events-worker → membership-worker`.
  Neither is new and neither is breaking anything. They matter because a cycle
  is the one shape static depth analysis cannot bound — on a cyclic path the
  only limit is the platform cap, reached by a bug rather than by design. Both
  are allowlisted so a third is a decision rather than a surprise.

  Depth and cycle set are pinned to their measured values, so a new service
  binding that deepens the worst case fails CI as a visible edit. The analysis
  functions are unit-tested on synthetic graphs, independently of the fleet.

- **2026-08-21: FT3's premise does not survive contact with the platform.** The
  milestone was to make per-hop cost readable from inside the product, so a
  free-tier operator would not need the paid dashboard the whole profile exists
  to avoid. Workers freeze timers as a Spectre mitigation — *"`Date.now()`
  returns the time of the last I/O. It does not advance during code
  execution"* — so every in-worker timer measures wall time across I/O and none
  can measure CPU. The existing `Server-Timing` seam is not under-built; it is
  measuring the only thing available to it.

  This also re-gates FT6. Its entry condition was "an FT3 measurement". FT3
  cannot produce one. The only source of CPU numbers is Cloudflare's own
  telemetry (*CPU Time per execution*, P50–P999, three-month retention), so
  that is what FT6 now waits on.

  What survives in FT3 is real and still worth building — hop count per request
  measures the 50-subrequest and 32-invocation budgets on live traffic, where
  FT2 can only bound them statically — but it has no single choke point. Each
  api-edge facade builds its own forward headers and each downstream worker
  forwards independently, so it means touching hot-path code in all 13 workers.
  Parked as a deliberate decision rather than absorbed into this epic.

- **2026-08-21: FT5 — the console was the real size risk, and minify was still
  on the table.** Measured with `wrangler deploy --dry-run`: 2296 KiB gzipped,
  75% of the free plan's 3072 KiB cap. Adding `minify: true` took it to 1880
  KiB (61%), a 416 KiB saving. FT0's fleet-wide minify pass had missed this one
  file, because it matched on `"minify": false` and the console config carried
  no `minify` key at all — a reminder that a sweep keyed on the wrong-value
  form silently skips the absent-key form.

  Two measurement traps, both hit before the guard was right. `.open-next/worker.js`
  is a ~2 KiB entry shim, not the bundle: the first version of the guard gzipped
  it, reported 1 KiB, and passed a budget of 1500 KiB — a guard that cannot fail
  is worse than none. And static assets (2.1 MB) must not be counted at all;
  they are served from the assets binding, free and unlimited, outside the
  script limit. The guard now shells out to a wrangler dry-run, which bundles
  exactly as the deploy does.

  It lives in the console's build lane rather than `tests/platform-limits`,
  because measuring costs a full Next build — minutes — and that suite's value
  is being cheap enough to always run.
