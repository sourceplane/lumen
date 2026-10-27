# web-console-next-tests

Verification suite for `web-console-next`.

A verify-only component: its lane runs this suite against `web-console-next` on every
plan that includes it. Nothing deploys from here — a red lane blocks the
convergence, which is the point.

## Gates

- `pnpm exec turbo run build --filter=./` — build
- `pnpm exec turbo run typecheck --filter=./` — typecheck
- `pnpm exec turbo run test --filter=./` — the suite itself
