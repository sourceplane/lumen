# Runbook

```sh
pnpm --filter @saas/platform-limits-tests test
```

## A gate went red

**"declares no crons at the top level of any worker"** — a `triggers` block was
added at the root of a wrangler template. Wrangler inherits it into every named
environment, so it costs one trigger per deployed environment rather than one
overall. Move it inside the environment that needs it.

**"declares crons only in the environment the free-tier profile deploys"** — a
non-prod environment took a cron slot. The free-tier profile budgets crons for
one environment; see `specs/profiles/free-tier.md` for what a second
environment costs and which slots are still spare.

**"keeps a single-environment deployment inside the free plan's 5"** — a new
scheduled job would put the account over the free-plan ceiling. Either fold the
work into an existing tick (gate it on the minute inside the handler), or move
the job to a Durable Object alarm, which costs no cron trigger. Spending the
spare slots is a decision to record in the profile spec, not a test to relax.

**"minifies every worker that opts into the setting"** — a worker set `minify`
to false. The free plan caps a worker at 3MB gzipped against 10MB on paid.
