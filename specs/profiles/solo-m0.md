# Profile: M0 / Solo (single-user B2C)

Status: Implemented · Owner: platform · Switch: `SOLO_MODE`

The **Solo** profile reduces the full multi-tenant baseline to a single-user B2C
product: the user never sees organizations, teams, projects, or platform
plumbing. It is achieved by **configuring the baseline _down_**, not by forking
or deleting anything.

## Design principles (non-negotiable)

- **Suppress, don't remove.** No worker deletions, no schema migrations, no
  data-layer changes. Every contract stays intact; the org/membership/project
  stack still exists and runs underneath.
- **One switch.** All M0 behavior keys off a single flag, `SOLO_MODE`. Turn it
  off and the full multi-tenant baseline is restored, unchanged. **M0 is a
  profile, not a fork.**
- **RBAC / billing / audit keep running** on their existing paths. The single
  user is the `owner` of their org and passes every policy check;
  one-subscription-per-org now simply reads as per-user.

## The switch

`SOLO_MODE` is a deploy-time flag, set in three places (all default to *off* in
code, so the baseline is the safe default; this Lumen instance turns it *on*):

| Surface | Where | Read by |
|---|---|---|
| **api-edge** | `apps/api-edge/wrangler.template.jsonc` → `vars.SOLO_MODE` (all envs) | `apps/api-edge/src/solo-mode.ts` → `isSoloMode(env)` |
| **identity-worker** | `apps/identity-worker/wrangler.template.jsonc` → `vars.SOLO_MODE` | `apps/identity-worker/src/solo-mode.ts` → `isSoloMode(env)` |
| **web-console-next** | `apps/web-console-next/next.config.mjs` → `env.NEXT_PUBLIC_SOLO_MODE` (default `"true"`) | `apps/web-console-next/src/lib/solo-mode.ts` → `SOLO_MODE` |

**To restore the full baseline:** set `SOLO_MODE` to `"false"` on api-edge and
identity-worker (re-render configs, redeploy) and build the console with
`NEXT_PUBLIC_SOLO_MODE=false`. Nothing else changes.

## Enforcement — blocked at the API edge

`apps/api-edge/src/index.ts` consults `isSoloSuppressed(path, method)` once,
before any facade dispatch, and returns **404** for a suppressed route. The
suppression policy (`apps/api-edge/src/solo-mode.ts`) reuses the existing facade
matchers, so it can never drift from the real routes.

**Suppressed (404 when `SOLO_MODE` is on):**

| Surface | Route(s) |
|---|---|
| Members | `/v1/organizations/:id/members[/:memberId]` |
| Invitations | `/v1/organizations/:id/invitations[/...]` |
| Projects & environments | `/v1/organizations/:id/projects[/...]`, `.../environments[/...]` |
| Metering / quotas | `/v1/organizations/:id/usage[/...]`, `.../quotas/...` |
| Outbound webhooks | `/v1/organizations/:id/webhooks/...` (+ project-scoped) |
| Integrations | `/v1/organizations/:id/integrations[/...]`, repo-links, `/ingress/github/*` |
| API keys | `/v1/organizations/:id/api-keys[/:keyId]` (M0-hidden; flag re-enables) |
| Second org | `POST /v1/organizations` |

**Kept and working (the single-user surfaces):**

- Auth — magic-link + social (OAuth), account/profile, security events
- Reading/using the one personal org — `GET /v1/organizations[/:id]`
- Per-user billing — checkout, portal, and the provider billing webhook
  (`/v1/billing/webhooks/polar`, which is distinct from outbound webhooks)
- Config — settings & feature flags
- Notifications (email), and **silent** audit logging

> Note: project-scoped config routes are technically still open at the edge, but
> are unreachable in Solo because no projects exist. The config *context* is
> intentionally kept (settings/flags are a Solo surface).

## Auto-provisioning — the invisible personal workspace

The end-state requires each user to get exactly one auto-provisioned, invisible
personal org with the `owner` role. This lives in the **auth/session path**:

- `apps/identity-worker/src/solo-mode.ts` → `ensurePersonalOrg(env, requestId, user)`
- Called from `handleLoginComplete` (magic-link) and `handleOAuthCallback`
  (social) right after a session is issued.

Properties:

- **Idempotent.** It first lists the user's orgs; a returning user is a no-op.
- **Race-safe.** New orgs use a deterministic slug (`personal-<userId>`), so a
  concurrent login that loses the create race hits a 409 (already exists) —
  treated as success, never a duplicate.
- **Owner role.** Reuses `POST /v1/organizations` unchanged; membership bootstraps
  org + member + `owner` role-assignment in one transaction. The first org is
  exempt from the multi-org billing gate, so no plan is required.
- **Best-effort.** Provisioning never fails a login; if membership is
  unreachable it no-ops and the next login retries. The internal
  identity→membership call bypasses the api-edge, so the edge's `POST` block does
  not affect it.
- **No new contract / no schema change.** It only calls existing endpoints with
  the standard actor headers.

The provisioned `subjectId` is the user's public id — the exact value the normal
request path resolves as the actor — so the membership record matches every
later request.

## Console behavior

- **No org switcher.** `SidebarOrgSwitcher` renders a static account chip (no
  dropdown, no "switch", no "view all", no "create org").
- **No "organization" wording.** Nav, settings groups, the switcher, and the
  General settings page relabel the tenant noun to **"Account"**
  (`TENANT_NOUN`). Pure nav models: `nav-items.ts`, `settings-nav.ts`.
- **Lands straight on the dashboard.** The org chooser (`/orgs`) auto-resolves
  the personal org and forwards — rendering a neutral placeholder (no
  "Organizations" heading, no "New organization" CTA) while it resolves, so org
  wording never flashes. The org root (`/orgs/:slug`) and post-auth landing go to
  the **Account (settings)** surface instead of Projects (which is suppressed).
  `/orgs/new` is blocked (bounces home).
- **Hidden surfaces** (nav + settings): members, invitations, projects,
  environments, usage/quota, webhooks, integrations, API keys. **Kept:** Account
  general, Notifications, Billing, Config (flags).
- **URLs are not refactored** — `/orgs/:slug/...` paths are kept and the personal
  org is auto-resolved into them (out of scope for minimum M0 to change URLs).

## Verification

- api-edge: `tests/api-edge/src/solo-mode.test.ts` — suppressed routes 404 and
  kept routes pass through with the flag on; the baseline is reachable with it
  off (47 assertions). Full api-edge suite stays green (403).
- identity: `tests/identity-worker/src/solo-mode.test.ts` — idempotent,
  race-safe, best-effort provisioning (10). Full suite green (174).
- console: `tests/web-console-next/src/{nav-items,settings-nav,last-org}.test.ts`
  — suppression + relabel + landing toggle with the flag; baseline unchanged.
  Full suite green (248).
- Build: `pnpm build` green (40/40) with Solo on; the console also builds with
  `NEXT_PUBLIC_SOLO_MODE=false`, confirming the baseline is restorable.

## Defaults chosen (M0 minimum)

- API keys: hidden in M0, re-enableable by flag (they are part of the suppressed
  set; remove them from `isSoloSuppressed` / settings-nav suppression to expose).
- `/orgs/:slug` routes kept; personal org auto-resolved — URLs not refactored.
- No projects auto-created (no Solo feature needs project scope).
