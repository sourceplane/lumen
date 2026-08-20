# platform-limits-tests

Structural guards on the **Cloudflare account limits** the whole worker fleet
deploys into, read straight off the committed `wrangler` templates.

These are not runtime tests. They defend limits that are per-account and only
bite at deploy time — after every other lane has gone green. The cron-trigger
ceiling is the motivating case: nothing in a worker's own config is wrong, the
arithmetic across all workers and all environments is, and the only feedback is
a failed deploy reading `This account has reached the Workers Free limit of 5
cron triggers per account`.

The budget these numbers come from is `specs/profiles/free-tier.md`.

## Gates

- No worker declares `triggers` at the top level, where every named environment
  inherits it (one declaration, one trigger per deployed environment).
- Only the environment the free-tier profile deploys (`prod`) declares crons.
- A single-environment deployment stays within 5 cron triggers.
- No worker ships with `minify` disabled, against the free plan's 3MB gzip cap.
