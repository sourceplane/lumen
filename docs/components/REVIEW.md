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

## The finding that was not a documentation problem

**26 components subscribed with `profile: quick-check`, and that profile runs no
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

**What the two profiles actually are**, read from stack-tectonic 0.20.0's own
`turbo-package` definitions rather than inferred:

| capability | `quick-check` | `verify` |
|---|---|---|
| setup-node, setup-pnpm, install | ✓ | ✓ |
| verify-structure | ✓ | ✓ |
| **pre-build** — where every suite here keeps its tests | — | ✓ |
| **build** | — | ✓ |
| **typecheck** | — | ✓ |

So `quick-check` skipped not only the tests but the build and typecheck as well.

### Two fixes, not one: the profile, and a guard in the composition

Flipping the profile was necessary and not sufficient. The pull request that
flipped it went green, and its `db-tests` lane reported seven steps where it
used to report four — exactly `verify`'s count. Neither of those is evidence
that a test ran, so the log was read:

```
✓  04 pre-build          0.0s  ·  Skipping pre-build.
✓  06 build-package      3.8s
✓  07 typecheck-package  2.3s
```

Pre-build skipped itself, for every component, whatever it declared. The guard
in stack-tectonic 0.20.0's `turbo-package` verify job reads a key orun never
sets:

```
{{if .preBuildCommand}}            ← orun's context has .orun, .parameters, .env
{{.parameters.preBuildCommand}}    ← where the value actually is
{{else}}
echo "Skipping pre-build."
```

`buildCommand` and `typecheckCommand` have the same mistake and only appear to
work: their guards are equally always-false, and their `else` defaults happen to
be the commands every component here declares. Pre-build has no default, so it is
the one that visibly breaks.

**The fix belongs upstream** — three guards in `sourceplane/stack-tectonic`,
each `.<key>` → `.parameters.<key>` — and could not be made there from this
change. stack-tectonic's own `main` is still `0.20.0` with the broken guards.
orun-cloud carries an in-tree copy that already reads `.parameters.*`, which is
why its suites run, and the proof the corrected guard works: its
`agents-worker-tests` pre-build ran for 29.9s and failed on real assertions.

**So the fix lives here until it ships there.** `stack-tectonic-fixes/` is
0.20.0's `turbo-package` with those three guards corrected and nothing else, and
`intent.yaml` binds that one composition type to it; every other composition is
still the pinned OCI artifact. It breaks this repository's rule that
compositions are not vendored, and it is fenced accordingly:

- `testing/composition-fixes.test.sh` undoes the three fixes and requires every
  file to hash to what 0.20.0 published, so the copy cannot become the place a
  step gets changed;
- the same gate fails on any stack-tectonic pin other than 0.20.0 while the
  directory exists, so moving the pin is when somebody decides whether the copy
  is still needed;
- the directory ships to products in `01-scaffold`, the phase that ships the
  `intent.yaml` naming it — a product's first plan needs both.

**Checked by rendering, not by reading.** `orun plan --all-envs` before and
after: 92 jobs and 610 steps either way, and exactly 19 steps differ — the
pre-build of the nineteen components below, from `echo "Skipping pre-build."` to
`pnpm exec turbo run test --filter=./`. A product placed and branded from the
blueprint receives the directory byte for byte and plans the same command.

### The profile, and the suites made ready to run

Nineteen components carry tests in `preBuildCommand`: the **seventeen**
`tests/*` suites and two packages with their own, `cli` and `sdk`. An earlier
draft of this page said sixteen; it was counting the overviews that read
`None`, and `platform-limits-tests` is a seventeenth suite with a real overview.

All nineteen now say `profile: verify` on `dev`, the only environment the
suites subscribe to and the one a pull request plans. `cli` and `sdk` keep
`quick-check` on `stage` and `prod`: a package does not deploy, so those rows
are its seat in each environment's graph, and running identical tests three
times would buy nothing. That matches how lumen's workers already subscribe —
plain `verify` on `dev`, with no rule skipping it on main.

**Before flipping anything, all nineteen were run locally exactly as `verify`'s
pre-build step runs them** (`pnpm exec turbo run test --filter=./` in each
component). Fourteen passed. Five did not, and in every case the test was right
about what it guards and its harness had drifted from the code underneath it.
The fifth was found by CI rather than locally: `web-console-next-tests` passed
here only from jest's transform cache, and its first real run, in a lane, could
not load four of its files. Every suite has since been re-run with no turbo
cache and an empty jest cache, in a tree staged the way orun stages a job.

| suite | what it hit | the fix |
|---|---|---|
| `api-edge-tests` | 12 tests read `apps/api-edge/wrangler.jsonc`, which no longer exists — each worker commits `wrangler.template.jsonc` and `tooling/wire/render.mjs` renders the deployable file (BF6) | read the template, which carries exactly the bindings asserted |
| `membership-worker-tests` | the same file, read at `describe` time, so the whole suite failed to load | the same |
| `db-tests` | `tsconfig.json` enumerates thirteen `@saas/db/*` subpaths and not `integrations`; jest resolved it through its `(.*)` catch-all, ts-jest's type-check did not | add the path |
| `integrations-worker-tests` | `tsconfig.json` maps `@saas/db/*`, which does not match bare `@saas/db` | add the path |
| `web-console-next-tests` | the console's sources import `@saas/sdk`; the suite's tsconfig and jest mapper named only `@saas/contracts`, so ts-jest could not resolve it and four files failed to load | map `@saas/sdk` to the sdk's source |

**And one that only a CI runner shows.** Eighteen test files across the worker
suites faked the database as `postgres://fake`. The list handlers read the
database concurrently with the membership call (PERF12) and wait for both, so
every such request made a real DNS lookup of the hostname `fake`. That fails in
milliseconds on a workstation; on a runner whose resolver does not answer it
waits out glibc's 5-second timeout, which is exactly jest's, and
`config-worker-tests` failed that way on its second CI run having passed its
first. Each now reads `postgres://fake@127.0.0.1:1/fake`, a closed loopback port
the kernel refuses at once with no lookup. Checked by delaying every lookup but
`localhost` by six seconds: the old URL times out seventeen tests in
config-worker alone, and with the change all nineteen suites pass with none.

The suites that failed *to load* were hiding more than their failure counts
showed: `membership-worker-tests` went from 85 tests to **269**, `db-tests` from
552 to **578**, `integrations-worker-tests` from 70 to **77**,
`web-console-next-tests` from 215 to **258**. **3,088 tests across the
nineteen**, every one passing on the finished tree.

**The repointed binding tests guard something real**, which was checked by
breaking it: pointing stage's `IDENTITY_WORKER` at `lumen-identity-worker-prod`
fails exactly the two tests written for it ("has stage service binding to
lumen-identity-worker-stage", "stage does not bind to prod identity worker").
A cross-environment binding would route stage traffic into prod's workers.

Not every `wrangler.jsonc` reference was rot. `config-worker-tests` renders the
template itself into a temporary file, `platform-limits-tests` tries the
template first, and `policy-worker` binds nothing, so it never moved to a
template and its `wrangler.jsonc` is real. None of those passes was vacuous.

### Left on `quick-check`, by design

`contracts`, `db`, `notifications-client`, `policy-engine`, `shared`,
`testing`, `webhook-verifier`. None has a `preBuildCommand`: their tests live
in the matching `tests/*` suite, which builds and typechecks them on every plan
that includes it. Moving them to `verify` would add their own build and
typecheck lanes — defensible, but a different change from making tests run.

### What this costs a build

Nothing, during a bootstrap. The nineteen verify on `dev` only, and a
bootstrap runs no `dev` lane: a landing's pull request is checked by `plan`
alone (`ci.yml` skips lanes on `orun/BASE-*`), and `01-scaffold` defers `dev`'s
push-to-main trigger until `08-docs` restores it
(`tooling/bootstrap/dev-lanes.mjs`). So the 18 measured minutes in
`docs/phases/TIMINGS.md` stand. An earlier draft of this section predicted the
suites would add to four phases' merge convergences; it had missed the defer.

After the bootstrap they run on every pull request and every merge to main, a
lane per suite beside the deploys. On this pull request's CI each suite's
pre-build took 3 to 13 seconds.

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

