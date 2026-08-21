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
| Cron triggers **per account** | 5 | 250 | Yes — 3 jobs × 2 envs was 6; now 3 |
| Subrequests per invocation | 50 | 10,000 | Yes — one outbound fetch per delivery; each binding hop also spends one |
| Requests | 100k/day, then error 1027 | unmetered | No — ~4.3k/day of crons at 1/min |
| Worker size | 3 MB gzip | 10 MB | **Only for the console** — 1880 KiB gzipped, 61% of the cap. Domain workers are 27–40 KiB |
| Hyperdrive | 10 configs, ~20 conns | 25, ~100 | No — the fleet uses one per env |
| Durable Objects | SQLite-backed only | + KV-backed | No — `RATE_LIMITER_DO` is SQLite-backed |
| Queues | 10k ops/day | 1M/mo | Not used |
| Workers per account | 100 | 500 | No — 28 across two envs |

### The chained-CPU constraint

CPU time is **summed across a service-binding chain and billed as one
request** — *"the total amount of CPU time used across both Worker A and
Worker B"* ([pricing][pricing]) — with a cap of 32 worker invocations per
request. So on the free plan

```
api-edge → integrations-worker → projects-worker → billing-worker
         → membership-worker → notifications-worker → events-worker → …
```

shares **one 10 ms budget across the whole chain**, including the JSON
serialize and parse at every hop. Lumen's worker-per-bounded-context
architecture is what conflicts with the free plan; the cron ceiling is only the
first symptom.

Measured from the prod service bindings, the deepest such chain is **8 worker
invocations**, from `api-edge` (`tests/platform-limits/src/service-chain.test.ts`).
That is comfortably inside the platform's hard cap of 32 invocations per
request, and it is the number that matters for CPU: eight workers, one budget.

The graph also contains **two cycles** —
`billing-worker → membership-worker → billing-worker` and
`membership-worker → notifications-worker → events-worker → membership-worker`.
They are long-standing and the fleet works, but they are worth naming: a cycle
is the one shape static analysis cannot bound, so on a cyclic path the only
limit is the platform cap, reached by a bug rather than by design. Both are
pinned in the guard so a third cannot arrive unnoticed.

This profile does **not** yet solve that. It removes the ceilings that can be
removed by configuration, and it bounds and pins the chain depth so the cost
cannot grow unobserved. Whether eight chained workers fit in 10 ms is still an
empirical question — see
[Open question: monolith mode](#open-question-monolith-mode).

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

**3 of 5 spent, 2 reserved.** `tests/platform-limits` prices the deployed set
and fails CI if that arithmetic breaks.

### The profile does not require a single environment

An earlier draft of this spec said the free-tier profile deploys one
environment. That was wrong, and worth correcting rather than quietly
softening: it conflated *where the crons live* with *how many environments
deploy*. Measured from the repo, the current two-environment fleet costs

| Per-account resource | Free plan | Spent | By |
|---|---|---|---|
| Cron triggers | 5 | **3** | `prod` only — stage carries none |
| Worker scripts | 100 | **28** | 14 components × 2 environments |
| Hyperdrive configs | 10 | **2** | one per environment |

Stage and prod together sit comfortably inside every per-account ceiling. What
has to be concentrated in one environment is the *crons*, because a trigger is
charged per deployed environment; nothing else in the fleet is close enough to
its limit to care. A third environment would cost 14 more worker scripts and
one more Hyperdrive config — still fine — and zero additional crons, as long as
they stay declared in `prod`.

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

## A Worker cannot measure its own CPU

This is a platform property, not a gap in our instrumentation, and it decides
how the open question below can ever be closed. Workers freeze timers as a
Spectre mitigation ([security model][security]):

> `Date.now()` returns the time of the last I/O. It does not advance during
> code execution.

So the clock only moves at I/O boundaries. Any in-worker timer — including the
`Server-Timing` phases in `packages/contracts/src/timing.ts` — measures **wall
time across I/O**, never CPU. That instrumentation is genuinely useful for
latency and for attributing database round trips, and it is worth keeping. It
simply cannot answer "does this chain fit in 10 ms of CPU", and no amount of
extra instrumentation in the product will change that.

What *is* measurable from inside a request:

| Quantity | In-worker? | Relevant limit |
|---|---|---|
| Hop count / subrequests | Yes | 50 subrequests, 32 invocations |
| Wall time across I/O | Yes | latency, DB round trips |
| **CPU time** | **No — frozen clock** | **10 ms per invocation** |

The only source of CPU numbers is Cloudflare's own telemetry: the dashboard's
*CPU Time per execution* chart (P50/P90/P99/P999, retained three months) and
the GraphQL Analytics API behind it.

## Open question: monolith mode

Whether the request path fits in 10 ms of chained CPU is unresolved, and per
the section above it cannot be answered from the code or from anything we ship.
It has to come from Cloudflare telemetry: read *CPU Time per execution* P99 for
`api-edge` and the workers it chains into.

FT2 measured the shape of the thing to be weighed: the deepest chain is **8
worker invocations**. Eight workers' CPU inside one 10 ms budget is the
question; the telemetry is the only scale.

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

`tests/platform-limits` (`@saas/platform-limits-tests`) reads the committed
wrangler templates and `component.yaml` files and fails on: a top-level
`triggers` block, crons declared outside `prod`, an account budget over any
free-plan ceiling, a worker with `minify` disabled, a
component-level **required** `secretEnv` whose ref hard-codes an environment,
or a per-environment `optionalSecretEnv` (a form orun silently drops). See its
runbook for what each failure means.

The budget suite **prices** the deployed set rather than forbidding a shape: it
computes which `(component, environment)` pairs a main-push convergence
deploys, applies wrangler's inheritance rule — a top-level `triggers` block is
charged to *every* deployed environment — and asserts the totals. A style rule
can be argued with; a number cannot. Reinstating the top-level block makes the
suite report `webhooks-worker · stage` as a fourth charge, which is precisely
the trigger that took the account to 6.

### The console bundle

The console is the one worker in the fleet whose size is a live constraint.
Measured with `wrangler deploy --dry-run`:

| | gzipped | % of the 3 MB cap |
|---|---|---|
| Unminified | 2296 KiB | 75% |
| **With `minify: true`** | **1880 KiB** | **61%** |

Minify was worth 416 KiB — 18% — and it was the one config the fleet-wide
minify pass missed, because `apps/web-console-next/wrangler.jsonc` carried no
`minify` key at all rather than an explicit `false`.

Two things are deliberately not counted. **Static assets** (2.1 MB) are served
from the assets binding: free, unlimited, and outside the script size limit —
so the console's real cost against the 100k requests/day budget is its
server-rendered routes only, not its page loads. And **`.open-next/worker.js`**
is a ~2 KiB entry shim, not the bundle; measuring it reports 1 KiB and passes
any budget, which is worse than no guard. The measurement therefore comes from
a wrangler dry-run, which bundles exactly as the real deploy does.

`apps/web-console-next/scripts/check-worker-size.mjs` runs in the console's own
build lane — the only lane where the artifact exists — and holds the bundle to
2400 KiB, below the hard cap so a failure arrives while there is still room to
act. It reports the figure on every build, not only on failure: the trend is
the useful part.

### Secret scoping

Deploy-time wiring documents are declared **per-environment**, under
`subscribe.environments[]` on `stage` and `prod` only — never at component
level, where orun attaches them to every job of the component as a required
reference regardless of profile or environment.

That is not a style preference. It is the difference between a dev lane that
renders offline from `wiring.fixture.json` and one that cannot start until a
prod credential resolves. When the Supabase integration connection was revoked
on 2026-08-06 and `WIRING_CLOUDFLARE_HYPERDRIVE` stopped being published, the
component-level form took every lane in every environment down with it —
`Secret not found`, before the first step, for two weeks. Scoping removed 26
required references from 12 dev jobs, verified against `orun plan`.

Verified at authoring time by rendering each scheduled worker from its wiring
fixture and running `wrangler deploy --dry-run --env prod`: wrangler accepts an
env-scoped `triggers` block (it reports unexpected keys in an env block, and
reports none here), and the three workers bundle to 27–40 KiB gzipped.

[limits]: https://developers.cloudflare.com/workers/platform/limits/
[security]: https://developers.cloudflare.com/workers/reference/security-model/
[pricing]: https://developers.cloudflare.com/workers/platform/pricing/
