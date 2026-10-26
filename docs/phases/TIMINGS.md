# Bootstrap timings — what a build takes, and where the number comes from

**This page used to open by admitting that no bootstrap had been measured end
to end.** One has: `pullely/multi-tenant-saas-2` built on 2026-10-26, 13:14 →
13:32 UTC, in **18 minutes**, and every number below is that run's own elapsed
rather than arithmetic on older ones.

The 45 these replace was honest arithmetic and **2.5x the truth**. Two of its
line items were not just conservative but wrong about the shape of the build,
and the run says which:

- **"Supabase project creation, 5–7m, is the floor and nobody can shorten
  it."** `03-infrastructure`, which creates the Supabase project *and* the KV
  namespace per environment and applies Terraform, took **2m5s** in total. The
  floor was not where the page thought it was.
- **`04-workers` at 14.** The twelve-worker fleet deployed to both
  environments in **3m53s**. The budget carried the memory of two convergences
  (a strip and a restore); there is one.

What the run confirms, as designed: **eight landings and no ninth** (PR #1
through #8 — `04-workers-restore` is gone), and `06-console` at **2m29s**
rather than the ~13 a cold Next.js build took, which is the fetched console
artifact doing what it was built to do.

## Per-phase budget

`expectedMinutes` is what the blueprint declares for each phase, and the
card's `bootstrap.expectedMinutes` is their sum (`testing/manifest.test.sh`
holds them equal). The phases' lines no longer quote it: a build page shows
one short line per step, and the budget is the engine's fact
(`.meta.expectedMinutes`), not prose.

**These are measured.** The column on the right is what the run took; the
declared number is that, rounded to the nearest whole minute. `08-docs`
finished inside the minute it started, and the card's reader requires a
positive number, so it declares 1.

| phase | budgeted | declared | measured on multi-tenant-saas-2 |
|---|---|---|---|
| `01-scaffold` | 2 | **1** | 1m15s |
| `02-foundation` | 5 | **3** | 2m30s |
| `03-infrastructure` | 8 | **2** | 2m5s |
| `03-infrastructure-database` | 5 | **3** | 3m2s |
| `04-workers` | 14 | **4** | 3m53s |
| `05-edge` | 4 | **2** | 2m21s |
| `06-console` | 5 | **2** | 2m29s |
| `08-docs` | 2 | **1** | under a minute |
| **total** | **45** | **18** | **18m wall clock** (17m35s of phases) |

**ONE RUN IS ONE SAMPLE**, and this page should not be read as a promise. What
makes it worth declaring anyway: it was a *fresh* account — no Supabase
project, no KV namespace, no Cloudflare worker, nothing cached — which is the
slow case rather than the fast one. What could still make a build slower than
18: Supabase or Cloudflare having a bad day, a GitHub Actions queue, and the
one condition on `06-console` below. A second measured run belongs on this
page beside the first rather than replacing it.

**One condition on `06-console`'s 2.** The console is fetched only when the
baseline tag being built from has a published artifact for exactly these
sources — `.github/workflows/tag.yml` publishes one as part of cutting a tag.
Without one, or when a product's console sources have changed, the pin is
absent or stale and the component builds from source: the phase is then its
old ~13 again, and nothing fails. 2 is the tagged case, which is every build
a product actually makes, and the measured run is one of them.

Not counted, because they are seconds rather than minutes, and real:
the task plane opened in the background (~23s per build), each landing
checked locally instead of by a runner (~24s per landing, eight of them),
and the convergence watch reading every 5s instead of 40 (~20s per landing).

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
