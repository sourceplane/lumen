# Component review — what each one declares, and how fully it is documented

Every one of lumen's **45 components**, scored on five measurable
signals. Generated against the tree, not typed by hand, so a number here is a
fact about the repository rather than an impression of it.

## The rubric

One point each, out of five:

| | signal | why it is the bar |
|---|---|---|
| 1 | `docs/overview.md` exists | the catalog's primary page for the component |
| 2 | `metadata.description` is set | without it the catalog row has no summary; orun emits the `Repo` entity from `description` alone |
| 3 | the overview carries 3+ headings | a title and one paragraph is a stub, however well written |
| 4 | the overview runs to 100+ words | enough to say what it is, what it needs and what breaks |
| 5 | 2+ further `docs.pages` are declared (architecture, runbook) | somewhere to put what the overview should not carry |

A 5 is not a ceiling on quality and a 3 is not a failing component — a small
pure package may deserve a short page. The scores are here to show **where the
documentation is thinnest**, not to rank the code.

## Scores

| component | domain | type | score | overview words | headings | description |
|---|---|---|---|---|---|---|
| `api-edge` | starter-runtime | cloudflare-worker-turbo | **5/5** | 209 | 3 | yes |
| `billing-worker` | starter-runtime | cloudflare-worker-turbo | **5/5** | 108 | 3 | yes |
| `integrations-worker` | starter-runtime | cloudflare-worker-turbo | **5/5** | 108 | 3 | yes |
| `membership-worker` | starter-runtime | cloudflare-worker-turbo | **5/5** | 166 | 3 | yes |
| `policy-worker` | starter-runtime | cloudflare-worker-turbo | **5/5** | 158 | 3 | yes |
| `projects-worker` | starter-runtime | cloudflare-worker-turbo | **5/5** | 108 | 3 | yes |
| `cloudflare-domain` | infra | terraform | **4/5** | 65 | 3 | yes |
| `cloudflare-hyperdrive` | infra | terraform | **4/5** | 87 | 3 | yes |
| `cloudflare-kv` | infra | terraform | **4/5** | 52 | 3 | yes |
| `supabase` | infra | terraform | **4/5** | 74 | 3 | yes |
| `contracts` | starter-contracts | turbo-package | **4/5** | 263 | 2 | yes |
| `db` | starter-data | turbo-package | **4/5** | 212 | 2 | yes |
| `admin-worker` | starter-runtime | cloudflare-worker-turbo | **4/5** | 58 | 3 | yes |
| `config-worker` | starter-runtime | cloudflare-worker-turbo | **4/5** | 72 | 3 | yes |
| `events-worker` | starter-runtime | cloudflare-worker-turbo | **4/5** | 82 | 3 | yes |
| `identity-worker` | starter-runtime | cloudflare-worker-turbo | **4/5** | 95 | 3 | yes |
| `metering-worker` | starter-runtime | cloudflare-worker-turbo | **4/5** | 75 | 3 | yes |
| `notifications-worker` | starter-runtime | cloudflare-worker-turbo | **4/5** | 85 | 3 | yes |
| `webhooks-worker` | starter-runtime | cloudflare-worker-turbo | **4/5** | 73 | 3 | yes |
| `admin-worker-tests` | starter-tests | turbo-package | **4/5** | 122 | 2 | yes |
| `api-edge-tests` | starter-tests | turbo-package | **4/5** | 122 | 2 | yes |
| `billing-worker-tests` | starter-tests | turbo-package | **4/5** | 122 | 2 | yes |
| `config-worker-tests` | starter-tests | turbo-package | **4/5** | 122 | 2 | yes |
| `contracts-tests` | starter-tests | turbo-package | **4/5** | 122 | 2 | yes |
| `db-tests` | starter-tests | turbo-package | **4/5** | 122 | 2 | yes |
| `identity-worker-tests` | starter-tests | turbo-package | **4/5** | 122 | 2 | yes |
| `integrations-worker-tests` | starter-tests | turbo-package | **4/5** | 122 | 2 | yes |
| `membership-worker-tests` | starter-tests | turbo-package | **4/5** | 122 | 2 | yes |
| `metering-worker-tests` | starter-tests | turbo-package | **4/5** | 122 | 2 | yes |
| `notifications-client-tests` | starter-tests | turbo-package | **4/5** | 122 | 2 | yes |
| `notifications-worker-tests` | starter-tests | turbo-package | **4/5** | 122 | 2 | yes |
| `platform-limits-tests` | starter-tests | turbo-package | **4/5** | 321 | 2 | yes |
| `policy-engine-tests` | starter-tests | turbo-package | **4/5** | 122 | 2 | yes |
| `policy-worker-tests` | starter-tests | turbo-package | **4/5** | 122 | 2 | yes |
| `projects-worker-tests` | starter-tests | turbo-package | **4/5** | 122 | 2 | yes |
| `web-console-next-tests` | starter-tests | turbo-package | **4/5** | 122 | 2 | yes |
| `db-migrate` | infra | db-migrate | **3/5** | 56 | 2 | yes |
| `cli` | starter-cli | turbo-package | **3/5** | 32 | 2 | yes |
| `sdk` | starter-sdk | turbo-package | **3/5** | 60 | 2 | yes |
| `notifications-client` | starter-shared | turbo-package | **3/5** | 57 | 2 | yes |
| `policy-engine` | starter-shared | turbo-package | **3/5** | 52 | 2 | yes |
| `shared` | starter-shared | turbo-package | **3/5** | 38 | 2 | yes |
| `testing` | starter-shared | turbo-package | **3/5** | 42 | 2 | yes |
| `webhook-verifier` | starter-shared | turbo-package | **3/5** | 53 | 2 | yes |
| `web-console-next` | starter-ui | cloudflare-workers-assets-turbo | **3/5** | 52 | 2 | yes |

Distribution: **5/5**: 6 · **4/5**: 30 · **3/5**: 9.

## What this pass changed

- **16 test overviews said `Verification suite for \`None\``** — a generator's
  absent field interpolated as the string `None`, committed, and inherited by
  every product built from this baseline. Each now names its real target
  component and lists its real gates, read from its own `component.yaml`.
- **23 components had no `metadata.description`** — every test component and
  all seven shared packages. All 45 now have one.
- **The seven shared packages opened with one interchangeable sentence**
  ("Shared workspace package. A shared package of the lumen workspace,
  consumed by the components below at build time"), which is true of all seven
  and says nothing about any. Each now opens with what it actually is.

## The finding that is not a documentation problem

**26 components subscribe with `profile: quick-check`, and that profile runs no
tests.** **Observed directly**, on the pull request that added this page — lumen's own
CI, not an inherited note. The `db-tests · dev · Verify` lane
([run 40296065423](https://github.com/sourceplane/lumen/actions/runs/40296065423))
ran four steps and stopped:

```
01 setup-pnpm                      6.3s
02 setup-node                     13.4s
03 install-workspace-dependencies  4.1s
04 verify-package-structure        0.0s
✓ Verify completed · 21.8s
  steps  4 passed, 0 failed, 0 skipped
```

`projects-worker-tests`, in the same lane, ran the same four. The suite's own
`preBuildCommand` — `pnpm exec turbo run test --filter=./` — never executed,
and `verify-package-structure` took 0.0s.

**The lane is named `· Verify`**, which is why nobody noticed: the check that
appears on a pull request, goes green, and satisfies branch protection is
titled Verify whatever profile it ran.

This repository had already written the finding down, in
`.github/workflows/baseline.yml`:

> It used to ride a `tests/flows` component whose `quick-check` profile runs
> setup, install and a package-structure check — and no tests (observed live
> on cirrus: `4 passed, 0 failed`, none of them a test).

Sixteen of the 26 are test suites whose tests live in `preBuildCommand`, which
`quick-check` skips.

The fix is one word per component — `profile: verify` — and it is **not in this
change on purpose**: flipping it turns on sixteen suites that have never run in
CI, and the right place to absorb that is a change that can watch what it
turns on, not one that is also moving the build's timings. orun-cloud hit the
identical hole and recorded it as the `packages/db` lesson (#1536); its test
components now say `verify` for exactly this reason.

Components on `quick-check`: `admin-worker-tests`, `api-edge-tests`, `billing-worker-tests`, `cli`, `config-worker-tests`, `contracts`, `contracts-tests`, `db`, `db-tests`, `identity-worker-tests`, `integrations-worker-tests`, `membership-worker-tests`, `metering-worker-tests`, `notifications-client`, `notifications-client-tests`, `notifications-worker-tests`, `platform-limits-tests`, `policy-engine`, `policy-engine-tests`, `policy-worker-tests`, `projects-worker-tests`, `sdk`, `shared`, `testing`, `web-console-next-tests`, `webhook-verifier`.

## Declared product URLs

Both environment doors and their links, probed 2026-10-26:

| URL | answer |
|---|---|
| `lumen-web-console-next-stage…workers.dev` | **200** |
| `lumen-web-console-next-prod…workers.dev` | 404 |
| `lumen-api-edge-stage…workers.dev` | 404 |
| `lumen-api-edge-stage…workers.dev/health` | 404 |
| `lumen-api-edge-prod…workers.dev` | 404 |
| `lumen-api-edge-prod…workers.dev/health` | 404 |

**The declarations are not wrong; the fleet is not deployed.** These are
`environments.<env>.url` and `links` in `intent.yaml`, which `rebrand.mjs`
rewrites per product — a product's own edge answers after `05-edge`, as the
measured build's probe confirms ("Both /health endpoints answered"). What the
404s say is that *this* repository's own fleet is absent from the Cloudflare
account it names, which is also why its convergence is red on the console
smoke. Rewriting the URLs would propagate a transient fact into every product.

The `github-dispatch` binding added in this change is the move that fixes it:
deploy `api-edge` to `stage` on its own, without a commit or a full
convergence.

## Catalog ref collisions (orun v2.89.0)

v2.89.0 refuses a domain, system or environment whose name gives it a
component's catalog ref — the component would be hidden in Orunbase. lumen is
clean: its domains are `infra, starter-cli, starter-contracts, starter-data, starter-runtime, starter-sdk, starter-shared, starter-tests, starter-ui`,
and no component shares a name with any of them. Nothing to change; checked so
that the next person does not have to.

