# Profile: Free Tier (Cloudflare Workers Free plan)

Status: Implemented (budgets + cron topology) · Owner: platform · Switch: `FREE_TIER`
Epic: [`saas-free-tier`](../epics/saas-free-tier/) — FT0 shipped; FT1–FT6 planned

The **Free Tier** profile runs Lumen on a Cloudflare account with no Workers
Paid subscription. Like [Solo](./solo-m0.md), it is achieved by **configuring
the baseline _down_**, not by forking or deleting anything: the same workers,
the same contracts, the same scheduled jobs — bounded so a single invocation
fits inside the free plan's ceilings.

## Design principles (non-negotiable)

- **Budget, don't disable.** No scheduled job is turned off. What changes is how
  much of its backlog one pass claims. Every job already resumes from a cursor
  or a retry schedule, so a smaller batch drains the same queue over more
  minutes rather than dropping work.
- **One switch.** Runtime behaviour keys off `FREE_TIER`, which defaults to
  *off* in code — the paid baseline is the safe default and the profile is
  strictly opt-in.
- **The cron topology is unconditional.** Declaring crons per-environment
  instead of at the top level is strictly better on either plan, so it is not
  behind the flag.

## The limits that actually bind

Measured against the [Workers limits][limits] and [pricing][pricing] docs.

| Limit | Free | Paid | Bites Lumen |
|---|---|---|---|
| **CPU per invocation** | **10 ms** | 30 s (→5 min) | **Yes — the hard constraint.** See below |
| Cron triggers **per account** | 5 | 250 | Yes — 3 jobs × 2 envs was 6 |
| Subrequests per invocation | 50 | 10,000 | Yes — one outbound fetch per delivery |
| Requests | 100k/day, then error 1027 | unmetered | No — ~4.3k/day of crons at 1/min |
| Worker size | 3 MB gzip | 10 MB | No — domain workers gzip to 27–40 KiB; only the OpenNext console is worth watching |
| Hyperdrive | 10 configs, ~20 conns | 25, ~100 | No — the fleet uses one per env |
| Durable Objects | SQLite-backed only | + KV-backed | No — `RATE_LIMITER_DO` is SQLite-backed |
| Queues | 10k ops/day | 1M/mo | Not used |
| Workers per account | 100 | 500 | No — ~26 across two envs |

### The chained-CPU constraint

CPU time is **summed across a service-binding chain and billed as one
request** — *"the total amount of CPU time used across both Worker A and
Worker B"* ([pricing][pricing]) — with a cap of 32 worker invocations per
request. So on the free plan

```
api-edge → integrations-worker → policy-worker → membership-worker → billing-worker
```

shares **one 10 ms budget across all five**, including the JSON serialize and
parse at every hop. Lumen's worker-per-bounded-context architecture is what
conflicts with the free plan; the cron ceiling is only the first symptom.

This profile does **not** yet solve that. It removes the ceilings that can be
removed by configuration. Whether the request path fits in 10 ms is an
empirical question — see [Open question: monolith mode](#open-question-monolith-mode).

## The switch

`FREE_TIER` is a deploy-time wrangler var, read by the two workers whose
scheduled passes are unbounded on the paid baseline.

| Surface | Where | Read by |
|---|---|---|
| **webhooks-worker** | `apps/webhooks-worker/wrangler.template.jsonc` → `vars.FREE_TIER` (all envs) | `apps/webhooks-worker/src/free-tier.ts` → `deliveryBudget(env)` |
| **integrations-worker** | `apps/integrations-worker/wrangler.template.jsonc` → `vars.FREE_TIER` | `apps/integrations-worker/src/free-tier.ts` → `drainBatchSize(env)` |

`metering-worker` needs no switch: its pass materializes exactly two fixed
windows with database-side aggregation, so it is bounded on either plan.

**To enable:** set `FREE_TIER` to `"true"` in the environment's `vars` block,
re-render the config and redeploy. **To restore the paid baseline:** set it back
to `"false"`. Nothing else changes.

### What the switch changes

| | Paid baseline | `FREE_TIER=true` |
|---|---|---|
| Events claimed per org per dispatch pass | 50 | 10 |
| Retryable attempts per sweep | 100 | 10 |
| Outbound deliveries per pass | unbounded | 20 |
| Inbound deliveries per drain pass | 50 | 10 |

`MAX_RETRY_BATCH = 100` on the paid baseline is not merely slow on the free
plan — it exceeds the 50-subrequest ceiling twice over and the pass is killed
mid-flight.

Dispatch and retry run in **one** invocation and therefore share its subrequest
budget: whatever dispatch spends, the retry sweep no longer has
(`apps/webhooks-worker/src/index.ts`). A pass that stops mid-fanout does not
advance the dispatch cursor, so subscribers it did not reach reclaim the event
next tick rather than losing it.

## The cron budget

The free plan allows **5 cron triggers per account** — across every worker *and*
every environment. A top-level `triggers` block in a wrangler config is
inherited by every named environment, so one declaration costs one trigger per
deployed environment. Three declarations across a stage + prod fleet is six
triggers, which is what produced

```
This account has reached the Workers Free limit of 5 cron triggers per account
```

Crons are therefore declared **inside `env.prod` only**:

| Worker | Cron | Job |
|---|---|---|
| `webhooks-worker` | `* * * * *` | Outbound dispatch + retry sweep |
| `integrations-worker` | `* * * * *` | Inbox drain: attribute → normalize → emit |
| `metering-worker` | `5 * * * *` | Usage rollup materialization |

**3 of 5 spent, 2 spare.** `tests/platform-limits` fails CI if a change breaks
that arithmetic.

Spending the spare two is a deliberate decision to record here. Before spending
one on a fourth job, prefer either of:

- **Fold it into an existing tick** — gate the work on the minute inside the
  `scheduled()` handler. Costs nothing.
- **A Durable Object alarm** — self-rescheduling, costs no cron trigger, and
  SQLite-backed DOs with alarms are free-plan eligible. Each `setAlarm()` is one
  row write against a 100k/day allowance, so a 1/min loop costs ~1,440/day.

Note that a *fan-out ticker* — one cron that calls the jobs over service
bindings — is the wrong shape here despite being the obvious one: it would put
the ticker and all three jobs inside a single 10 ms CPU budget.

## What the profile gives up

- **Background jobs in stage.** Only `prod` carries crons. Stage still serves
  requests and still accepts inbound webhooks; nothing dispatches or drains
  them. Verifying delivery end-to-end is a prod-only exercise, or costs one of
  the two spare slots.
- **Latency on a backlog.** A 20-delivery ceiling at one pass per minute is
  1,200 deliveries/hour. Past that the queue grows; the cursor and retry
  schedule mean it drains rather than drops, but a spike takes longer to clear.
- **Headroom, not correctness.** 100k requests/day is a hard stop that returns
  error 1027, not a throttle.

## Assumes Solo

This profile is specified on top of [Solo](./solo-m0.md) (`SOLO_MODE=true`,
Lumen's default). Solo means one org, which is what makes the dispatcher's
per-org loop a loop of one — a fair-scheduling problem the free-tier budgets do
not otherwise solve. Running `FREE_TIER=true` with `SOLO_MODE=false` and many
active orgs would let orgs early in `listActiveOrgIds()` starve later ones,
because a pass stops when its delivery budget is spent. Fixing that needs a
rotating org cursor, which is out of scope until a multi-org free-tier
deployment is a real case.

## Open question: monolith mode

Whether the *request* path fits in 10 ms of chained CPU is unresolved and
cannot be answered by reading the code. The cheap experiment, from a paid
account: read CPU-time p50/p99 per worker off the dashboard for `api-edge` and
the workers it chains into.

- **p99 comfortably under 10 ms** → the profile is complete as specified.
- **p99 over 10 ms** → no amount of cron or batch budgeting helps, and the
  profile needs a *monolith mode*: bundle the domain contexts into one worker
  and dispatch in-process, removing the per-hop serialize/parse entirely. That
  is a structural change and gets its own spec.

One thing to measure first either way: `@saas/db` uses `postgres.js` and both
scheduled workers carry `perf(db): reverted to per-request DB client`. A fresh
Postgres connection performs SCRAM-SHA-256 auth — PBKDF2 at the server's
iteration count — in the worker, per request. Invisible under 30 s; potentially
the dominant cost under 10 ms.

## Guards

`tests/platform-limits` (`@saas/platform-limits-tests`) reads every committed
wrangler template and fails on: a top-level `triggers` block, crons declared
outside `prod`, more than 5 crons in a single-environment deployment, or a
worker with `minify` disabled. See its runbook for what each failure means.

Verified at authoring time by rendering each scheduled worker from its wiring
fixture and running `wrangler deploy --dry-run --env prod`: wrangler accepts an
env-scoped `triggers` block (it reports unexpected keys in an env block, and
reports none here), and the three workers bundle to 27–40 KiB gzipped.

[limits]: https://developers.cloudflare.com/workers/platform/limits/
[pricing]: https://developers.cloudflare.com/workers/platform/pricing/
