# saas-bootstrap-factory — implementation status (as-built)

As-built record for the BF epic. Distinct from `implementation-plan.md` (intent)
and `README.md` (at-a-glance). One row per shipped milestone, newest first.

| Milestone | Status | What shipped | PR |
|-----------|--------|--------------|----|
| BF12 (rename-map slice) | 🛠️ Partial | `tooling/rebrand/rebrand.mjs` + `FORKING.md`: the deterministic rename map BF12 specced, shipped ahead of the blueprint/instantiator as a standalone zero-dep script. Codifies the orun-cloud fork's transformation log: repo slug, product domain (org-owned forms masked: orun backend URL, `sourceplane.io`, company mailboxes), display name vs. `Lumen` code identifier (markdown-aware: code fences/inline spans keep the identifier form), CLI bin (packages/cli scope + doc examples), worker-name prefixes, wire-visible UAs, branded env vars (incl. `LUMEN_CONFIG_DIR` in CLI tests — a rename the fork needed), workers.dev subdomain, localStorage prefix. Leftover sweep fails on missed baseline identity (`--verify` re-runs it); idempotent; clean-tree guard; writes `ai/context/fork-from-baseline.md` provenance. Rehearsed end-to-end: toy rebrand of this repo → sweep clean, second run no-op, full typecheck (48 tasks) + test suite (28 tasks) green on the rebranded tree. Blueprint/instance contracts + `factory instantiate` remain BF11/BF12 proper. | _this PR_ |
| BF6b (fleet) | ✅ Shipped | Deploy-time wiring rolled out to the remaining 11 workers (admin, billing, config, events, identity, integrations, membership, metering, notifications, projects, webhooks), completing BF6: `wrangler.jsonc` → committed `wrangler.template.jsonc` with `@@wiring(cloudflare-hyperdrive/<env>:hyperdrive_id)@@` tokens, per-app `wiring.fixture.json` + `wire:fixture` script, component wiring parameters; rendered configs gitignored. The deploy profile renders the fixture before build/typecheck (#336) — the gap the first instantiation (orun-cloud) hit when its deploy lane built templated workers with no committed config. `tests/config-worker/src/deployment-config.test.ts` re-anchored from account-pinned IDs to the BF6 invariants and made hermetic (it renders templates itself via `tooling/wire/render.mjs`; it had been red on fresh checkouts since the pilot gitignored api-edge's rendered config). `apps/api-edge/scripts/verify-bindings.mjs` re-anchored the same way. `grep -rn "08f7c605\|ab2c21c2" .` is now empty (BF6 done-when). Conversion mirrors the rollout proven live by orun-cloud PRs #6–#9. | #337, #338, _this PR_ |
| BF6 (pilot) | 🛠️ In progress | Deploy-time wiring shipped end-to-end for `api-edge` (the worker with both Hyperdrive + KV bindings). `tooling/wire/render.mjs` (zero-dep) renders `wrangler.jsonc` from a committed `wrangler.template.jsonc` whose `@@wiring(<component>/<env>:<key>)@@` tokens resolve from the BF5 Secrets Manager manifest; fails loudly on any unresolved token. Composition gains guarded steps: `wire-fixture` (verify/PR lanes, offline render from committed `wiring.fixture.json` — D5 resolved) and `wire-credentials`+`wire-live` (deploy lane, OIDC plan role + `aws secretsmanager get-secret-value`). `verify-structure` now rejects committed 32-hex resource IDs in templates (CI guard). api-edge's committed `wrangler.jsonc` deleted + gitignored; `pnpm wire:fixture` renders for local dev. All 13 worker components carry the (inert until templated) `awsAccountId`/`owner`/`repo`/`orgName` params so the shared deploy profile's use-step cannot render an empty role ARN. `dependsOn: cloudflare-hyperdrive, cloudflare-kv` added to api-edge (stage/prod edges verified in DAG; dev correctly unaffected). Verified locally: fixture render, secrets-dir render, unresolved-token failure, offline `wrangler deploy --dry-run` against fixture-rendered config, full+changed orun plans. Remaining for BF6 done: fleet rollout (BF6b) + live stage/prod deploy proof via wire-live. | _this PR_ |
| BF5 | ✅ Shipped | Wiring manifest: `cloudflare-hyperdrive` and `cloudflare-kv` now publish their consumable outputs (`hyperdrive_id`/`hyperdrive_name`; `api_edge_idempotency_kv_id`/`_title`) to AWS Secrets Manager as Terraform resources (stable secret container + rotating version, mirroring the supabase pattern). D2 resolved: Secrets Manager. D3 resolved with a refinement: per-component wiring paths are simply each component's **conventional** `<org>/<repo>/<component>/<env>` secret path (already inside the deploy role's `sourceplane/lumen/*` write scope) — no new `/wiring/` namespace. Also parameterized the hardcoded supabase secret path in hyperdrive's data source to `${var.orgName}/${var.repo}/...`. `cloudflare-domain` wiring keys deferred to BF7 (v5 re-import restores real outputs). BF6 consumes these at deploy time. | _this PR_ |
| BF4 | ✅ Shipped | Generalized the Hyperdrive binding name: `LUMEN_DB` → `PLATFORM_DB` (decision D1) across all 12 DB-bound worker `wrangler.jsonc` files (stage+prod blocks, including `integrations-worker`), every `env.ts` type and `env.` accessor (~145 files in `apps/` + `tests/`), and the `saas-integrations` design doc. No alias period: a Worker's binding config and code bundle ship in one atomic `wrangler deploy`, so there is no skew window (recorded in `ai/context/decisions.md`, superseding the dual-read mitigation in `risks-and-open-questions.md`). Verified: fleet-wide `pnpm typecheck` (48 tasks) and the full test suite (28 tasks) green. | _this PR_ |
| BF3 | ✅ Shipped | App identity via config indirection: one identity seam per app — `apps/api-edge/src/app-config.ts` (workers.dev subdomain, console worker prefix, origin builder; `cors.ts` consumes), `apps/web-console-next/src/lib/app-config.ts` (product name/title/description, api-edge target URLs, sales email, localStorage namespace; consumed by `lib/api.ts`, `layout.tsx`, login, org settings, billing cards, `session.tsx`, `last-org.ts`), `apps/webhooks-worker/src/app-config.ts` (delivery User-Agent), `packages/cli/src/brand.ts` (bin name, default API URL, keychain service, config dir + env var; consumed by `cli-runner.ts` help, `auth/login.ts`, `token-store/keychain.ts`, `config-paths.ts`). cors tests build fixtures (incl. the suffix-attack origin) from the seam. Console smoke command now uses `${WORKERS_DEV_SUBDOMAIN}` instead of a duplicated literal. Boundary (recorded): the `@saas/sdk` class name `Lumen` and code comments are code identifiers, deferred to the BF12 rename map — not runtime identity. Verified: typecheck across 9 affected tasks, 353 api-edge tests + cli + webhooks suites green, `your-workers-subdomain` exists in exactly the two app-config seams. | _this PR_ |
| BF2 | ✅ Shipped | Parameterized the identity surface so the shared stack is account-agnostic. AWS account ID lifted out of all three Stack Tectonic role-ARN job templates (`terraform-validate`, `cloudflare-domain-validate`, `db-migrate-run`) to `{{.parameters.awsAccountId}}`, sourced from `intent.yaml` `parameterDefaults.terraform` (terraform components) and `infra/db-migrate/component.yaml` (migration runner); added `awsAccountId` to the three schemas. Supabase org/region moved from hardcoded `locals` in `main.tf` to required TF variables fed by `supabaseOrgId`/`supabaseRegion` component parameters. Bootstrap README de-literalized. Verified pure refactor via rendered `plan.json`: role ARNs unchanged (`306024784101`…`-plan`) and `TF_VAR_supabaseOrgId='dwazxcrywsdbxpuouifa'` / `TF_VAR_supabaseRegion='ap-southeast-1'` — no Terraform diff. `grep` confirms neither literal remains in `stack-tectonic/` or any `.tf`. | _this PR_ |
| BF1 | ✅ Shipped | Encoded the real infra dependency DAG as `dependsOn` edges: `supabase → bootstrap`, `cloudflare-hyperdrive → supabase`, `db-migrate → supabase` (alongside existing `db-migrate → db`); `cloudflare-kv` left independent. Verified with `orun validate` + `orun plan --view dag` — edges resolve per-environment in stage and prod, no cycle. Confirmed the cross-env `dependsOn` limitation only affects components with no overlapping environments; recorded in `ai/context/decisions.md`. | _this PR_ |
| BF0 | ✅ Shipped | Docs truth pass: rewrote root `README.md` to the real component inventory + status (was claiming Workers/Hyperdrive/migrations unimplemented); removed the personal `/Users/irinelinson/.local/bin/kiox` path from all active docs in favor of `kiox`; made `kiox.yaml` the single source of truth for the Orun runtime version (dropped the stale `v2.3.0` literals in `orun-golden-path.md` and `access-and-infra.md`). `specs/_archive/` left frozen as historical record. | _this PR_ |

## Notes

- BF0 is docs-only: `specs/` and root docs are not Orun discovery roots, so the
  compiled plan DAG is unchanged and CI produces no component jobs.
- Follow-on milestones (BF1+) begin changing `component.yaml` and Stack Tectonic
  contracts and will produce real plan/verify jobs.

## The workers.dev subdomain, read from the Cloudflare connection (2026-10-21, `baseline-v30`)

Ported from cirrus-baseline (its #30). `subdomain` was a typed field on the
console card, though it belongs to the Cloudflare account the same way its id
does and has exactly one right answer: a wrong one surfaced only after deploy,
in CORS, OAuth origins, smoke checks and the verify URLs.

`blueprint.yaml` now declares `from: connection.cloudflare.workersSubdomain`.
The Cloudflare integration reads the subdomain from the account at connect and
on its hourly health check, and the bootstrap door fills the input from the
connection the build is BOUND to — the same one `CLOUDFLARE_ACCOUNT_ID` and the
deploy tokens mint from. The console renders no field for it, and an account
with no workers.dev subdomain refuses the build at the door, naming the fix.

- `testing/manifest.test.sh` accepts the source and requires its provider to be
  in `spec.requires.integrations` (cirrus's block, byte for byte). The card
  already lists `cloudflare`.
- `repo-blueprint.yaml`, `BOOTSTRAP.md`, `docs/phases/01-scaffold.md` and
  `docs/phases/README.md` say a hand-run build still passes `--set subdomain`.
- Cirrus also marked a BE3 "not probed" note superseded and answered its risk
  #13. Lumen carried neither, so this section is the whole record.

| check | result |
|---|---|
| manifest, phases, coverage, rebrand | all pass |
| mutation: `cloudflare` removed from the card's `spec.requires.integrations` | `manifest.test.sh` fails (exit 1) naming `inputs[subdomain]` — "there is no connection to read it from"; restored, it passes |
| `orun new --status`, `testing/leak.test.sh`, `testing/placement.test.sh` (orun 2.58.11, the CI pin) | pass — 1103 files derived and placed, unchanged |

## The `domain` input, removed (2026-10-21, `baseline-v30`)

Ported from cirrus-baseline (its #31). `07-domain` was the one conditional
phase: `when: inputs.domain`, off by default, landing a single component,
`cloudflare-domain`. That component ships PARKED — `subscribe.environments:
[]` — so CI plans no lanes for it and the phase's convergence was a green run
with nothing in it. A landing that deploys nothing, behind a switch that turns
on a component which is already off, was one more question and one more PR for
no effect. Cirrus has one landing and folded the component into `01-product`;
Lumen keeps its landings, so it folds into `06-console`, the last landing that
converges a deploy and the one that places `web-console-next`, which the
component routes and `dependsOn`.

### What shipped

- `repo-blueprint.yaml`: the `domain` input is gone, and with it the
  `"domain"` key of the `.rebrand/values.json` template; `cloudflare-domain`
  joins `06-console`'s modules; the `07-domain` phase is deleted. Nine phases
  remain; the numbering keeps its gap so `08-docs` keeps its name. `08-docs`
  already required `06-console`.
- `blueprint.yaml`: the programme lists seven milestones; `07-domain` (and its
  `when: domain`) is gone.
- `tasks/07-domain.TaskContract.yaml` and `docs/phases/07-domain.md` are
  deleted. What the page said that is still true — the component ships parked,
  its custom-domain attachment is fenced off mid-migration to provider v5, the
  zone must exist in the account first, wiring it is restoring the
  commented-out `subscribe` block — is now a section of
  `docs/phases/06-console.md`, and `ai/context/operations.md` (which ships)
  says the same without naming a factory path.
- `06-console`'s task contract leaves `cloudflare-domain` out of `affects`:
  that list is what the convergence deploys, and a parked component deploys
  nothing.
- `tests/fixtures/acme.json` loses `"domain": false`.

### What the tests had to become

- `testing/phases.test.sh` has no FOLDED map, so its partition records the
  move in place: `06-console` expects `cloudflare-domain`, with a comment
  saying why, and the gate still proves the component moved whole and nothing
  moved with it.
- `testing/leak.test.sh` and `testing/placement.test.sh` no longer force
  `domain` on: `06-console` places the component on every build, so the gates
  cover it without help. The placement tier's phased sequence now places
  `08-docs` after `06-console` — it requires the drifted `06-console`, the
  exact case BE-O12 fixed.
- `testing/manifest.test.sh` (comments only) no longer lists `domain` among
  the blueprint's build-driving inputs.

### Verification

| check | result |
|---|---|
| manifest, phases, coverage, rebrand | all pass — 7 milestones agree; 9 phases, 65 modules |
| `orun new --status` (orun 2.58.11, the CI pin) | parses; nine phases derived |
| `testing/leak.test.sh` (orun 2.58.11) | pass — 1103 files derived, 2 context files, no factory paths |
| `testing/placement.test.sh` (orun 2.58.11) | pass — 1103 product files, the same count as with `domain` forced on before; `01 → 08` place through the rebrand; `--resume` keeps the branding |
| derived file set against `main` with `domain=true` | identical: 1103 files, and `06-console`'s 186 are exactly `main`'s 06-console (176) plus 07-domain (10) |

## The domain is set later (2026-10-22, `baseline-v30`)

Ported from turso-starter (its #9). The console card asked for the product's
domain, with help text that said it did not need to exist — and nothing in
the build needed one: the product answers on workers.dev from its first
deploy, every phase probes workers.dev, and the one component that attaches
a domain, `cloudflare-domain`, ships parked. The owner asked for the domain
to stop being an input at bootstrap, with the logic that uses it kept where
it is so it can be set later. Ships in `baseline-v30` with #115: the tag was
never pushed, and the owner pushes it at this PR's merge commit, so the one
release carries the subdomain source, the removed `domain` switch and this.

### What shipped

- `blueprint.yaml` declares no `productdomain` and no `apibaseurl`. The card
  derived `apibaseurl` as `https://api.{productdomain}`, and a card can only
  derive from inputs it declares, so it left with the domain. The console's
  Product step asks for the display name alone.
- `repo-blueprint.yaml`: `productdomain` is optional, default `""`, and its
  description names where the domain goes and how it is set later;
  `apibaseurl`'s description states the CLI rule below. The values template
  still writes `"productdomain": ""`. A hand-run build may pass
  `--set productdomain=` for a product that already has its domain.
- `tooling/rebrand/rebrand.mjs` no longer requires `productdomain`. Empty, it
  brands the reserved placeholder `<reponame>.example.com` (RFC 2606) where
  `lumen.app` stood — intent's `BASE_DOMAIN` and `CONSOLE_CUSTOM_DOMAIN` (the
  parked `cloudflare-domain`'s parameters, and the component's own
  `baseDomain`), api-edge's `CONSOLE_CUSTOM_DOMAIN` (CORS), identity-worker's
  `OAUTH_ALLOWED_CONSOLE_ORIGINS` (which also lists the workers.dev console,
  so sign-in works without a domain), the notifications sender
  `no-reply@mail.<domain>`, billing's `POLAR_SUCCESS_URL`, and the edge's
  CORS test fixtures. No component logic changed. Lumen's Supabase root
  configures no auth URLs, so nothing there names the domain.
- The CLI's default API. `apibaseurl` fell back to `https://api.<domain>`,
  which with the placeholder is a host that can never answer. With no domain
  it is now the product's own prod edge on workers.dev,
  `https://<brandSlug>-api-edge-prod.<subdomain>.workers.dev` — the worker
  rule's name for `lumen-api-edge` deployed `--env prod`, live from the first
  deploy. With a domain it stays `https://api.<domain>`; an explicit
  `apibaseurl` still wins.
- `hooks/render-deployment-docs.sh` already probed the custom domain only
  when `.rebrand/values.json` records one, so the empty value skips it; it
  now also treats the `*.example.com` placeholder as no domain, and its
  narration no longer names the removed `07-domain`.
- The shipped `ai/context/operations.md` gains "Setting the domain later":
  every place the domain goes, then replace the placeholder
  (`git grep -lF`), create the zone and restore `cloudflare-domain`'s
  commented-out `subscribe` block, verify the mail domain, Supabase auth URLs
  (none configured), re-point the CLI default if wanted, merge, run the docs
  flow. It names the baseline's `lumen.app`, which the rebrand turns into
  the product's own placeholder, and no factory path.
- `BOOTSTRAP.md`, `docs/phases/README.md`, `docs/phases/01-scaffold.md` and
  the required-inputs sentence of five phase pages: three required inputs
  (`reponame`, `productname`, `githuborg`); `productdomain` NOT ASKED;
  `06-console.md` and `08-docs.md` say the custom domain is the placeholder
  until set. The troubleshooting row for a missing input names
  `productname`.

### What the tests had to become

- `tests/fixtures/acme.json` carries no domain, so the leak gate and the
  placement tier exercise exactly what a console build supplies.
- `testing/placement.test.sh` read the card's `derive` and exited "gone
  blind" without it. It now checks the value a no-domain product gets: its
  `DEFAULT_API_URL` must be the PLACED, BRANDED api-edge's wrangler name plus
  `-prod` on the fixture's subdomain (with `--env prod` read from its
  `component.yaml`), and every `BASE_DOMAIN` / non-empty
  `CONSOLE_CUSTOM_DOMAIN` in its `intent.yaml` must be the placeholder. It
  refuses to pass on nothing: a fixture with a domain or an `apibaseurl`, a
  missing worker name, deploy env, `DEFAULT_API_URL` or `BASE_DOMAIN` each
  fail it.
- `testing/rebrand.test.sh` gains nine checks: no domain and an empty domain
  brand the placeholder; the OAuth origins keep the workers.dev console; the
  no-domain CLI default is the prod edge, follows `brandSlug`, and survives
  three passes; a given domain brands itself and `https://api.<domain>`; an
  explicit `apibaseurl` wins.
- `testing/manifest.test.sh` (comment only): the derive-agreement check has
  nothing to hold today and stays for the next derived input.
- `baseline.yml`'s blueprint read sets no domain, so CI proves the document
  resolves without one.

### Verification

| check | result |
|---|---|
| manifest, phases, coverage, rebrand | all pass — 7 milestones agree; 9 phases, 65 modules; 45 of 45 components; rebrand 23 checks (14 before) |
| `orun new --status` with no `productdomain` (orun 2.58.11, the CI pin) | parses; nine phases derived |
| `testing/leak.test.sh` (orun 2.58.11) | pass — 1103 files derived, unchanged; 2 context files, no factory paths |
| `testing/placement.test.sh` (orun 2.58.11) | pass — 1103 product files, unchanged; `DEFAULT_API_URL` is `https://acme-cloud-api-edge-prod.acme.workers.dev`; the placeholder `acme-cloud.example.com` in `BASE_DOMAIN` ×3 and `CONSOLE_CUSTOM_DOMAIN` ×2, 10 files carry it; `01 → 08` place through the rebrand |
| mutation: the old CLI rule (`https://api.<domain>` always) | `rebrand.test.sh` fails 3 checks, `placement.test.sh` fails naming `https://api.acme-cloud.example.com`; restored, both pass |
| mutation: no placeholder (empty domain stays empty) | `rebrand.test.sh` fails 3 checks, `placement.test.sh` fails on `BASE_DOMAIN ''`; restored, both pass |
| the documented replacement, on a placed product | `git grep -lF acme-cloud.example.com` lists 10 files; the `perl` one-liner leaves 0, and `BASE_DOMAIN` reads `acme.dev` |
