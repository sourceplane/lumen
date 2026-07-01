# Forking Lumen into a new SaaS

Lumen is a reusable, self-contained baseline: fork it, rebrand it, deploy it
as a new product. The mechanical rename is one script; everything that needs
human hands (cloud accounts, secrets, OAuth apps) is the checklist below. The
process has been proven end-to-end by real instantiations; the friction each
found is folded back in here (see §5 for the hard-won bring-up details).

## 1. Create the repo

Either GitHub-fork this repo or import a history-free snapshot
(`git archive` → new repo), which is what the first instantiation did. A
snapshot keeps the new product's history clean; upstream syncs become manual
cherry-picks.

## 2. Rebrand (scripted)

Write a values file (start from `tooling/rebrand/values.example.json`):

```jsonc
{
  "repoName": "acme-cloud",          // repo slug: intent name, component repo:,
                                     // Secrets Manager paths, OIDC role names,
                                     // Supabase project names
  "productName": "Acme Cloud",       // display name: console, CLI copy, docs
  "productDomain": "acme.dev",       // BASE_DOMAIN, console custom domains,
                                     // OAuth origins, billing success URLs
  "brandSlug": "acme",               // worker-name prefix + user-agent slugs
  "cliBin": "acme",                  // CLI binary / keychain / ~/.config dir
  "workersDevSubdomain": "...",      // your Cloudflare workers.dev subdomain
  "salesEmail": "sales@acme.dev"     // optional; omit to keep the baseline mailbox
}
```

Then, on a clean tree:

```bash
node tooling/rebrand/rebrand.mjs --values my-brand.json --dry-run   # inspect
node tooling/rebrand/rebrand.mjs --values my-brand.json             # apply
git diff --stat                                                     # review, commit
```

The script applies the deterministic rename map (repo slug, product domain,
display name, SDK class `Lumen` → your PascalName, CLI bin, **every
Cloudflare worker resource name**, wire-visible user agents, branded env vars,
workers.dev subdomain), runs a leftover sweep that fails on any missed baseline
identity, writes a provenance record to `ai/context/fork-from-baseline.md`, and
is idempotent — rerunning it is a no-op. `node tooling/rebrand/rebrand.mjs
--verify` re-runs just the sweep at any time.

> ✅ **Forks are Cloudflare-account-safe.** `rebrand.mjs` brand-prefixes every
> worker's deployed name — the top-level wrangler `"name"`, every
> `"<worker>-<env>"` service binding, smoke health-check and binding test — so
> a fork's workers (`acme-membership-worker-stage`, …) never collide with the
> baseline's, even when the fork *shares* the baseline's account. The KV
> idempotency namespace self-brands via `${var.repo}` for the same reason. The
> orun *component* identity (dependsOn, `component.yaml` metadata, paths) is
> deliberately left generic — only the deployed CF identity is branded.
> Giving the fork its own Cloudflare account is still cleaner, but no longer
> required to avoid clobbering the baseline. (Earlier forks had to prefix all
> workers by hand; that is now mechanical.)

It deliberately does **not** touch org-owned identity:

| Kept as-is | Why |
|---|---|
| GitHub org (`owner:`, `namespace:`, `github.com/sourceplane/...`) | The org, not the product |
| `apiVersion: sourceplane.io/v1` manifests | Schema identifier owned by the orun tooling |
| `https://orun-api.sourceplane.ai` | orun state backend (`intent.yaml`) |
| S3 state buckets, Terraform `orgName`/`owner` defaults | Org-scoped shared infra (owned by `aws-admin`) |
| GitHub App slugs | Registered apps; slugs are globally unique (re-register, step 3) |
| npm scope `@saas/*` | Already product-neutral (decision D4) |
| Company mailboxes (unless `salesEmail` is set) | Real inboxes |

If you fork *under a different GitHub org*, the org-owned column is yours to
re-point too (intent `namespace`, component `owner:`/`orgName:`, state
buckets, the orun backend URL) — that is an infrastructure move, not a
rebrand, and is intentionally out of the script's scope.

## 3. Alternative: incremental (per-component) forks

The snapshot path above copies everything at once. If you want a fork that
grows a few components per PR — smaller reviews, smaller CI fan-outs, or a
deliberate subset of the platform — use `tooling/fork/components.mjs`. It
builds the *complete* prerequisite graph (declared `dependsOn`, wrangler
service bindings, deploy-time wiring inputs, workspace package dependencies,
tests-follow-their-subject) and orders/validates copies against it.

**Step 0 — scaffolding (no components).** Create the new repo with the
non-component skeleton: `intent.yaml`, `kiox.yaml` + `kiox.lock`,
`.github/workflows/ci.yml`, `stack-tectonic/`, `tooling/`, root
`package.json`, `pnpm-workspace.yaml`, `pnpm-lock.yaml`, `turbo.json`,
`.gitignore`, and the docs you want. CI plans an empty job matrix and is
green before any component exists.

**Step 1 — rebrand the source once.** Run the rebrand script on a scratch
clone of the baseline (see above) and copy batches *from that clone*, so
every copied file arrives already rebranded.

**Step 2 — copy in order.** Ask the tool for the order, then copy one batch
per PR:

```bash
node tooling/fork/components.mjs --order                 # numbered batches
node tooling/fork/components.mjs --copy policy-worker \
  --from ../baseline-rebranded                           # one batch per PR
git add -A && git commit                                 # lockfile included!
```

`--copy` brings each component's directory plus its `tests/` package, then
resyncs `pnpm-lock.yaml` (`pnpm install --lockfile-only`) and re-validates
the dependency closure. The resync matters: worker CI installs with
`--frozen-lockfile`, and pnpm requires the lockfile's importer set to match
the workspace exactly — every batch that adds or removes components must
commit the resynced lockfile. Resolutions stay pinned to the baseline's;
only the importer set changes.

At any time, `node tooling/fork/components.mjs --check` verifies that every
prerequisite of every component present in the tree is also present, and
names exactly what to copy next if not.

**Ordering facts the tool encodes:**

- All `packages/*` ship as one foundation batch — they are verify-only (no
  cloud), and the test suites' cross-package dependencies make finer slicing
  not worth it.
- Infra goes `bootstrap → supabase → cloudflare-hyperdrive → db-migrate`
  before any DB-bound worker; `cloudflare-kv` only before `api-edge`;
  `cloudflare-domain` last.
- `billing-worker`, `membership-worker`, `events-worker`,
  `notifications-worker` form a **service-binding cycle** and must be copied
  (and first deployed) as one batch. On a fresh account this cycle **cannot
  bootstrap on its own** — Cloudflare rejects a deploy whose service binding
  targets a worker that does not exist yet (error `10143`), and re-running the
  workflow does not help because the cycle never resolves. Break it with the
  `cycle-break.mjs` two-pass tool (§5).
- The console's deploy **smoke health-checks `api-edge`**, so it carries
  `dependsOn: api-edge` (in `apps/web-console-next/component.yaml`) — without
  that edge its first convergence races api-edge's deploy and fails with `curl`
  exit 22 (404). The console is also only *usable* once `api-edge` and
  `identity-worker` are live.

The `tests/config-worker` guard suite is partial-tree safe (its api-edge
sections skip when api-edge is not yet copied), so CI stays green at every
intermediate state.

## 4. Operator checklist (per instance, by design)

Nothing here can be scripted from inside the repo; budget a working session
with the right account owners. Track progress in your generated
`ai/context/fork-from-baseline.md`.

- [ ] **GitHub Actions secrets**: `CLOUDFLARE_ACCOUNT_ID`,
      `CLOUDFLARE_API_TOKEN` (Workers+KV+Hyperdrive+DNS scopes),
      `SUPABASE_API_KEY`, **`SUPABASE_ORG_ID`** (the `supabase` Terraform
      reads it as `TF_VAR_supabaseOrgId` to create the projects; the first
      `supabase` apply fails without it).
- [ ] **Cloudflare account**: its own account is cleaner, but reusing the
      baseline's is now safe — `rebrand.mjs` brand-prefixes every worker name
      and the KV title self-brands (§2), so a fork no longer overwrites the
      baseline's live workers.
- [ ] **AWS** (via the org's `aws-admin` repo): GitHub-OIDC roles
      `<env>-github-<org>-<repoName>-{plan,production-deploy}` per
      environment, plus Secrets Manager write scope `<org>/<repoName>/*`.
      State buckets are shared org infra and already exist.
- [ ] **Supabase**: org access for the management token. The
      `<repoName>-stage` / `<repoName>-prod` projects are created by the
      `supabase` Terraform component on first apply — no manual creation.
- [ ] **Cloudflare**: account + real `workersDevSubdomain` (put it in the
      values file before rebranding, or rerun with it set), zone for
      `productDomain`, DNS delegation; `stage.<domain>`/`prod.<domain>`
      attach via the `cloudflare-domain` component.
- [ ] **OAuth apps** (GitHub + Google, per env): set the client IDs in
      `apps/identity-worker/wrangler.template.jsonc` vars (the committed
      baseline IDs are the baseline's; they are non-secret but useless to
      you) and load the secrets with `wrangler secret put`.
- [ ] **GitHub Apps** for the integrations cluster (per-env registration;
      see `specs/epics/saas-integrations/`).
- [ ] **Billing**: Polar (or Stripe) products and the env secrets the
      billing-worker expects.

## 5. First-boot expectations (learned the hard way)

- PR (verify) lanes plan Terraform only. The `cloudflare-hyperdrive` plan is
  **red on PRs until the first `main` apply** has written the Supabase
  credentials document to Secrets Manager. Expected; it converges after the
  first merge.
- After that first apply, workers deploy with bindings resolved from the
  wiring manifest — there are no committed resource IDs anywhere (BF6), so a
  fresh account needs no hand-pasted Hyperdrive/KV IDs.
- **Re-run the full workflow**, never "re-run failed jobs": orun's remote
  state keys on `<run>-<attempt>` and a partial re-run deadlocks.
- **Keep PRs to a few components.** Fleet-wide PRs fan out 30–70 CI jobs and
  starve the runner pool (the first instantiation split its rollout into
  four PRs for this reason). A batch of ~12–18 jobs (4–5 components) converges
  reliably; bring components up in dependency order (see the recovery playbook
  below). To re-converge a component without a code change, append a one-line
  `# ci: <reason> (<timestamp>)` comment to its `component.yaml` — orun's
  change-scoped planner re-plans only the touched components.
- **The console already declares `dependsOn: api-edge`.** Its deploy smoke
  curls `<brand>-api-edge-<env>/health`; the edge (in
  `apps/web-console-next/component.yaml`) keeps its deploy lane ordered after
  api-edge so the smoke does not race a 404.
- **`dev` lanes for data-bound workers are expected red.** `dev` has no
  Supabase/Hyperdrive/KV wiring, so the `*-dev` verify/deploy lanes for workers
  that need the data layer fail by design. Judge bring-up by `stage`/`prod`.
- `stage`/`prod` converge on merge to `main` behind `requireApproval: true`
  — someone has to approve the deploy lanes.

### Bootstrapping the service-binding cycle (two-pass)

The `{billing, membership, events, notifications}` cluster (§3) cannot deploy
on a fresh account: each worker binds another that does not exist yet, and
Cloudflare rejects the deploy (`10143`). Re-running does not help.
`tooling/bootstrap/cycle-break.mjs` automates the two-pass fix:

1. **Strip the feedback edges** — `node tooling/bootstrap/cycle-break.mjs
   --strip`. This removes the two minimal feedback bindings (`billing →
   membership`, `membership → notifications`, the edges in
   `ACKNOWLEDGED_BINDING_CYCLES`), replacing each with a self-describing
   marker. Commit, trigger the four cluster components, and merge — they now
   deploy in order `policy → billing → membership → events → notifications`.
2. **Restore the edges** — `node tooling/bootstrap/cycle-break.mjs --restore`,
   then commit + merge. `membership` and `notifications` now exist, so
   Cloudflare accepts the restored bindings; only `billing` + `membership`
   redeploy. `--restore` reproduces the templates byte-for-byte, so the cluster
   is back to its exact original topology. (`--check` reports current state.)

These are deploy-config bindings only — the worker `Env` types and the
(fetcher-mocking) tests are unaffected, and the `deployment-config` cycle test
only shrinks its checked set in pass 1.

### Recovering a partially-failed fleet convergence

When a large convergence partially fails (timeouts / runner starvation),
recover in small dependency-ordered batches rather than re-running the whole
fleet:

1. Identify what actually deployed (worker `/health`, Terraform state).
2. Re-trigger the rest layer by layer, one PR each: **infra → leaf workers
   (policy, admin) → the cycle cluster via the two-pass above →
   membership-dependents (config, metering, webhooks, projects, identity) →
   `api-edge` → console**. Each layer's dependencies must be live before it.
3. Verify each layer (`<brand>-api-edge-<env>/health` returns `ok`, including
   its database check) before starting the next.

## 6. Upstream syncs

A snapshot fork has no shared git history: sync by cherry-picking content
and re-recording it in `ai/context/fork-from-baseline.md`. The longer-term
answer (blueprint/instantiator with provenance lock and `factory upgrade`)
is specced as BF11–BF14 in `specs/epics/saas-bootstrap-factory/`.
