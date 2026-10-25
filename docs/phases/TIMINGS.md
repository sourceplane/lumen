# Bootstrap timings — what to budget, and where the numbers come from

**Provenance matters here.** No bootstrap has been measured end to end under
the current numbers. The budgets below are arithmetic on measured runs — the
runs themselves are described under the table — and the second item that used
to head this page, *"every landing waits for its PR's CI again"*, is no longer
true: a bootstrap landing's pull request runs `plan` alone
(`.github/workflows/ci.yml`) and the landing is checked locally before it is
pushed (`checks: local`), so nothing waits for a runner to re-do work the
merge is about to do for real.

What remains true from that header: **phase 03 is two landings** — the flows
landed supabase, kv, hyperdrive and db-migrate in one PR without waiting on
it, while the blueprint lands supabase and kv, waits for the apply, then
lands hyperdrive and db-migrate (see
[03-infrastructure.md](03-infrastructure.md)).

## Per-phase budget

`expectedMinutes` is what the blueprint declares for each phase, and the
card's `bootstrap.expectedMinutes` is their sum (`testing/manifest.test.sh`
holds them equal). The phases' lines no longer quote it: a build page shows
one short line per step, and the budget is the engine's fact
(`.meta.expectedMinutes`), not prose.

**These are re-budgeted, not re-measured.** The 84 they replace was the sum
under the old shape; three changes took time out of every phase, and the
column on the right is the arithmetic, from the measured runs below and from
`pullely/multi-tenant-saas` (2026-10-25, baseline before these changes).

| phase | was | now | why |
|---|---|---|---|
| `01-scaffold` | 2 | **2** | unchanged. Measured ~2m (vela), 1m35s (multi-tenant-saas) |
| `02-foundation` | 9 | **5** | vela's 9m was PR verify lanes 3m29s + convergence 3m56s. The PR pass is gone (`plan` only on a bootstrap branch) |
| `03-infrastructure` | 9 | **8** | Supabase project creation, 5–7m, is the floor and nobody can shorten it. The PR pass (1m28s on multi-tenant-saas) is gone |
| `03-infrastructure-database` | 6 | **5** | measured 7m20s on multi-tenant-saas, of which its PR pass was 1m25s |
| `04-workers` | 31 | **14** | vela's 31m was PR lanes ~7m + strip convergence 13m18s + restore convergence 10m54s. One fleet deploy and no PR pass leaves the 13m18s |
| `04-workers-restore` | 5 | **gone** | the fleet deploys once, with its bindings (`tooling/deploy/fleet-stubs.mjs`) |
| `05-edge` | 5 | **4** | measured 5m22s (vela) / 5m03s (ambient) including its PR pass |
| `06-console` | 16 | **5** | measured 15m37s / 14m01s, nearly all of it the cold Next.js build. The console is now FETCHED, not built (saas-console-artifact CA4): the Cloudflare-only baseline measured the build step at 0.6s and the whole console job at 1m13s–1m22s, two environments |
| `08-docs` | 1 | **2** | it also restores the promotion gate and dev's lanes now |
| **total** | **84** | **45** | |

Not counted, because they are seconds rather than minutes, and real:
the task plane opened in the background (~23s per build), each landing
checked locally instead of by a runner (~24s per landing, eight of them),
and the convergence watch reading every 5s instead of 40 (~20s per landing).

**One condition on `06-console`'s 5.** The console is fetched only when the
baseline tag being built from has a published artifact for exactly these
sources — `.github/workflows/tag.yml` publishes one as part of cutting a tag.
Without one, or when a product's console sources have changed, the pin is
absent or stale and the component builds from source exactly as before: the
phase is then its old ~13 again, and nothing fails. The budget is for the
tagged case, which is every build a product actually makes.

**What the earlier measurements were.** Two real Lumen bootstraps, both under
the shell layer that `repo-blueprint.yaml` replaced, and both before any of
the changes above:

- **vela** (2026-07-30) — fully headless phased bootstrap into the `seafern`
  workspace with only `ORUN_TOKEN` + `GITHUB_TOKEN`. Landings waited for PR
  checks, and PR lanes then deployed. ~73m for 01–06.
- **ambient** (2026-08-02) — fully headless again, with a workspace-scoped
  `sk_` API token (baseline-v8, orun v2.52.4). Landings merged without
  waiting on PR checks. ~60m for 02–06.

And one under the blueprint, which did not finish:

- **pullely/multi-tenant-saas** (2026-10-25) — reached the end of
  `03-infrastructure-database` in 21m35s and `04-workers`' PR check in
  30m46s, then stopped: 46/46 PR jobs green, no merge, no convergence, no
  further platform event. Nothing failed. Its `ORUN_TOKEN` is the likeliest
  cause (`orun auth token` mints ~30m); every retry afterwards died on the
  pen branch that build left behind, which is what
  `tooling/bootstrap/pen-reset.mjs` now clears. Its 04-workers PR ran 46 jobs
  in 6m49s — the duplicated pass that item 1 of this re-budget removes.

**Replace these with measurements.** After the first full bootstrap under
these numbers, take each phase's elapsed time from its `done` event
(`--progress json`) and edit this table and the blueprint's `expectedMinutes`
together. An estimate that survives its first real run unchanged is a
document nobody checked.

## Things that shape the total

1. **Every landing waits for its PR, and that is deliberate.** The flows
   went the other way — `--no-wait` on phases 02–06, one convergence per
   landing, because PR lanes then deployed the fleet a second time (and,
   for 04's restore, a third). That is most of the drop from vela's 04 to
   ambient's. Waiting came back once PR lanes stopped deploying and phase 03
   was split so its PRs could pass — the split the old version of this page
   proposed as the "check-friendly alternative" to `--no-wait`.
2. **Supabase project creation (5–7m) is irreducible** from our side —
   budget for it; nothing to engineer around short of pre-provisioning
   projects.
3. **Watch GitHub Actions billing.** A full bootstrap is hundreds of runner
   minutes. A tripped spending limit presents as lanes that "fail" with NO
   logs anywhere — the message lives only in the check-run ANNOTATIONS
   (`gh api repos/<o>/<r>/check-runs/<job-id>/annotations`).
4. **A session token will not outlive the run.** `orun auth token` mints a
   short-lived one (~30m); a full `--resume` is longer. Use the workspace's
   admin-role API key as `ORUN_TOKEN`, mint a session token per phase, or —
   as the platform's own runner does — point `ORUN_TOKEN_FILE` at a file
   something keeps fresh: the CLI re-reads it on every call and prefers it
   over `ORUN_TOKEN`.
5. **A convergence that follows a commit touching NO components** plans zero
   lanes and reads "green". The phase's verify hook is the real gate; never
   trust a green run without one. (It is why the parked custom-domain
   component no longer has a landing of its own: as `07-domain` it was
   exactly this case. It lands in `06-console` now.)

## Defect log from the measured runs

Found and fixed during the two measured bootstraps, and listed so nobody
re-hits them. Some fixes lived in the shell layer and went with it; the
right-hand column says where each one lives now.

| fix | what broke on a fresh product | now |
|---|---|---|
| #50 | `secret://` refs: segment 1 is the WORKSPACE — the repo-slug rebrand rewrote both segments; every resolve failed `Validation failed` | a rebrand rule |
| #52 | `cloud check` passed without the LOCAL link cache (fresh HOME) | `01-scaffold`'s `link` hook runs `orun cloud link` before the check, every time |
| #53 | the workspace-slug self-heal dirtied the tree before its own clean-tree check | shell-layer only; gone with it |
| #54 | later phases branded fresh baseline content with the product's scaffold-era copy of the rebrand tool | every hook runs `{{ .baseline.dir }}/tooling/rebrand/rebrand.mjs`, and no product carries the tool |
| #55 | supabase `adopt.tf` read `SUPABASE_ORG_ID`, but the job env carries `TF_VAR_supabaseOrgId` | `adopt.tf` accepts either |
| #56/#57 | phase 03's PR lanes structurally red on first boot | then: a `--no-wait` landing. Now: the 03 split |

What the workspace-scoped (`sk_`) token path surfaced on ambient, all fixed
then:

1. `sk_` tokens see NO memberships list → slug resolution needs
   `orun workspace <ws>` (v2.52.1), the direct org read.
2. `sk_` tokens cannot write repo links → the repo must be linked by the
   platform or allow-listed in the console; `01-scaffold`'s `link` is best
   effort for exactly this reason and `cloud check` is the gate.
3. The intent declares the project SLUG; config-surface and state routes
   take `prj_…` ids → CLI-side slug resolution (v2.52.2 secrets, v2.52.4
   run). The product's `ci.yml` lane pin is v2.56.2 today (the phase
   overlay's floor was v2.56.0; v2.56.2 is where a branded tree stopped
   refusing its next phase).
4. A step `timeout:` did not kill grandchildren — a wedged git held the
   step's pipes past its deadline (15m declared, 71m observed) → process-
   group kill + WaitDelay (orun v2.52.3).
5. git has NO transfer timeout → the shell layer set
   `http.lowSpeedLimit/Time` on every git call.
6. git's credential `store` fires EVERY configured helper (system
   osxkeychain included) → in a keychain-less HOME securityd can raise a
   BLOCKING dialog on the console user's screen, hanging the step until a
   human clicks. The shell layer used a get-only credential helper.

Items 5 and 6 were guards on the shell layer's own git calls. The network
git work is now orun's (the landing's pen and `orun.repo/ensure@v1`); this
page has not verified that those carry both guards, and a bootstrap that
hangs on a git push or a keychain prompt should be read with them in mind.
