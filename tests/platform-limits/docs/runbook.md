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

**"declares no component-level required secret that hard-codes an
environment"** — a `secretEnv` entry under `spec:` points at a literal
`/dev/`, `/stage/` or `/prod/` rung. orun attaches component-level `secretEnv`
to every job of the component, in every environment, as a required reference,
so this makes jobs resolve credentials they never read — and resolution runs
*before* the first step, so a missing value kills the lane with `Secret not
found` and nothing built. Two fixes, depending on what the secret is:

- The job needs *its own* environment's value → template it:
  `secret://<ws>/<project>/{{ .environment }}/<KEY>`.
- Only some environments need it (a deploy-time wiring document, say) → declare
  it per-environment under `subscribe.environments[]`, on those environments
  only. This is what the twelve worker components do for
  `WIRING_CLOUDFLARE_HYPERDRIVE`.

**"declares no per-environment optionalSecretEnv"** — an `optionalSecretEnv`
block inside a `subscribe.environments[]` item. orun **silently drops** it: no
error, no warning, the reference never reaches the job. Either move it to
component level (where the optional form works, for every environment) or make
it a per-environment `secretEnv` if it is genuinely required there.
