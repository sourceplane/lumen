# Bootstrapping this product

This product boots **entirely against its Orun Cloud workspace** (the
`workspace:` in `intent.yaml`; a fork carries provenance in
`.orun/provenance.*.lock` and `ai/context/fork-from-baseline.md`) — CI holds
no provider credential; every secret is brokered from the workspace's
integrations at run time. Every command below takes the workspace org slug;
the examples write `<org>`.

## One-time operator prerequisites

The workflow preflights each of these and stops with instructions if missing:

1. **CLI login** — `orun auth login --device`, approve the code at
   `https://app.orun.dev/cli/device` in a browser session that belongs to the
   workspace owner. (When the operator is an agent, the Claude Chrome
   extension can fill and submit the approval form — the CLI itself cannot.)
2. **Integrations** — connect **Cloudflare** (paste an Account API token per
   the in-console recipe; the same account may already back other workspaces
   — that is supported) and **Supabase** (OAuth; pick the organization that
   should own this product's projects) in the console → Integrations.
3. **Repo allow-list** — the workspace must trust this repo's CI identity
   (OIDC). `orun cloud check --org <org>` verifies; granting is done in the
   console (Git Repos) — the CLI cannot grant it. `orun cloud link` must have
   been run from a clone with a GitHub remote (it records the numeric repo id
   the OIDC exchange resolves by).
4. **AWS (org-owned, via `aws-admin`)** — the per-repo GitHub-OIDC roles
   (`<env>-github-sourceplane-<repo>-plan`) and the Terraform state prefix.
   Without them the `bootstrap` Terraform batch fails at its first plan.

## The workflow

```bash
orun workflow run flows/bootstrap-flow.yaml --set org=<org>
```

- **preflight** — auth, allow-list, integrations present.
- **create-secrets** — five project-rung secrets from the integrations
  (workers-deploy / hyperdrive-edit / account-id / management-access /
  org-id). Brokered and fact templates only: no value is ever typed or seen.
- **batches** — every deployable component starts *parked*
  (`subscribe.environments: []`, originals stashed in
  `flows/subscriptions/`). Each batch step un-parks a group, opens a PR,
  requires its checks green, merges, then requires the merge's main
  convergence run (the deploy + per-worker smoke) green before the next
  batch starts:

  | # | batch | components |
  |---|---|---|
  | 1 | infra-foundation | cloudflare-kv |
  | 2 | data-a | supabase (its secretOutputs lease-publish the DB creds the next batch reads) |
  | 3 | data-b | db-migrate, cloudflare-hyperdrive |
  | 4 | workers-a | policy, membership, events, projects |
  | 5 | workers-b | identity, config, webhooks, notifications, metering, admin |
  | 6 | workers-c | billing, integrations |
  | 7 | edge | api-edge |
  | 8 | console | web-console-next |

  `cloudflare-domain` stays parked until the `lumen.app` zone exists in the
  Cloudflare account.
- **verify-live** — curls the deployed api-edge + console endpoints on both
  environments and fails on any dead endpoint.

Every step is also runnable by hand (`flows/batch.sh <name> <components…>`,
`flows/create-secrets.sh <org>`), and a failed batch resumes by re-running the
workflow — completed batches are no-ops (their components are already
un-parked and deployed). `create-secrets` also self-heals: a key whose
integration connection was revoked (health `orphaned`) is revoked and
recreated against the current ACTIVE connection.

## Runtime worker secrets (wire-now-seed-later)

Workers declare their runtime keys in `optionalSecretEnv` + `runtimeSecrets`
(OAuth client secrets, Polar keys, `SECRET_ENCRYPTION_KEY`, …). They are
**inert until seeded**: add a value in the console (Secrets → New secret) or
via `orun secrets set <KEY> --org <org> --env <env>` and the next deploy pushes
it to the worker via the stack's `secrets-live` step. No repo change per
secret.
