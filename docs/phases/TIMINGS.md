# Bootstrap timings — what to budget, and where the numbers come from

**Provenance matters here.** Every measured number on this page comes from
one of two real Lumen bootstraps, and both ran under the shell layer
("the flows") that `repo-blueprint.yaml` replaced. **No bootstrap has been
measured end to end under the blueprint yet.**

- **vela** (2026-07-30) — fully headless phased bootstrap into the `seafern`
  workspace with only `ORUN_TOKEN` + `GITHUB_TOKEN`. Landings waited for PR
  checks, and PR lanes then deployed. Times are the clean path, with every
  fix the run produced already landed.
- **ambient** (2026-08-02) — fully headless again, with a workspace-scoped
  `sk_` API token instead of a user session (baseline-v8, orun v2.52.4).
  Landings merged without waiting on PR checks (one deploy per landing),
  which had shipped between the two runs.

What moved into orun's typed actions is the mechanism, not the work: for
most phases the numbers carry over. Two changes do move the clock, and the
table labels every row that is an estimate because of them:

1. **Phase 03 is two landings.** The flows landed supabase, kv, hyperdrive
   and db-migrate in one PR without waiting on it. The blueprint lands
   supabase and kv, waits for the apply, then lands hyperdrive and
   db-migrate (see [03-infrastructure.md](03-infrastructure.md)). Neither
   half has been timed.
2. **Every landing waits for its PR's CI again** — orun ≥ v2.58.6 waits for
   the whole PR run and merges only on green. Unlike vela's, today's PR
   lanes do not deploy (`ci.yml` gates deploy and apply profiles on a push to
   `main`), so the wait costs build, test and plan time rather than a second
   deploy. That should land between vela and ambient; it is not measured.

## Per-phase budget

`expectedMinutes` is what the blueprint declares and what the narration
quotes to an operator ("About N minutes").

| phase | `expectedMinutes` | provenance | what was measured | dominated by |
|---|---|---|---|---|
| `01-scaffold` | 2 | measured | ~2m (vela) | render + rebrand ~1m · repo create + push ~30s · link ~10s |
| `02-foundation` | 9 | measured | ~9m vela (PR verify lanes 3m29s · convergence 3m56s); 5m08s ambient | verify lanes, twice |
| `03-infrastructure` | 9 | **estimate** | the old one-landing phase 03: ~10m vela (convergence 6m47s), ~15m ambient (convergence ~11m) | Supabase project creation, 5–7m |
| `03-infrastructure-database` | 6 | **estimate** | — (its work was inside the old phase 03's numbers) | PR plan lanes · Hyperdrive create · migrations |
| `04-workers` | 31 | measured — **for both landings** | ~31m vela (PR lanes ~7m · strip convergence 13m18s · restore convergence 10m54s); 20m49s ambient | the fleet deploy |
| `04-workers-restore` | 5 | **estimate** | — as its own phase; its convergence was the 10m54s inside vela's 31m | billing + membership redeploy |
| `05-edge` | 5 | measured | 5m22s vela; 5m03s ambient | land → converge → `/health` probes |
| `06-console` | 16 | measured | 15m37s vela (all 3 resumes, self-healed); 14m01s ambient (0 resumes) | console builds are heavy |
| `07-domain` | 5 | **estimate, never run** | — | today its convergence plans nothing ([07-domain.md](07-domain.md)) |
| `08-docs` | 1 | **estimate** | — (neither run's table records it) | probe + render + land |
| tracking (BT) | seconds per landing | **estimate** | — | one task lookup and at most two creates per landing, plus the epic once |

**Totals.** Measured: ~73m for 01–06 on vela, ~60m for 02–06 on ambient. The
card (`blueprint.yaml`) promises ~60–75 minutes and budgets 75. The
per-phase numbers above sum to 84 without `07-domain` — they overstate,
because `04-workers`' 31 is vela's figure for the old phase 04, which already
contained the restore landing that `04-workers-restore` budgets again.
Budget **60–75 minutes**, and treat the 04 pair as ~20–31 between them.

**Replace the estimates with measurements.** After the first full bootstrap
under the blueprint, take each phase's elapsed time from its `done` event
(`--progress json`) and edit this table and the blueprint's
`expectedMinutes` together. An estimate that survives its first real run
unchanged is a document nobody checked.

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
   trust a green run without one. (`07-domain` is exactly this case today.)

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
