# notifications-worker-tests

Verification suite for `notifications-worker`.

A verify-only component: its lane runs this suite against `notifications-worker` on every
plan that includes it. Nothing deploys from here — a red lane blocks the
convergence, which is the point.

## Gates

- `pnpm exec turbo run build --filter=./` — build
- `pnpm exec turbo run typecheck --filter=./` — typecheck
- `pnpm exec turbo run test --filter=./` — the suite itself
