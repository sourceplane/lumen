# Measured bootstrap timings — and the path to a smooth full bootstrap

Measured on the `vela` instantiation (2026-07-30): fully headless phased
bootstrap into the `seafern` workspace, run by remote reference with only
`ORUN_TOKEN` + `GITHUB_TOKEN`. Times are the CLEAN path — what a fresh
product pays today with every fix this run produced already landed.

## Per-phase wall-clock (vela, measured)

| phase | time | dominated by |
|---|---|---|
| 01 scaffold | **~2m** | blueprint render + rebrand ~1m · repo create + push ~30s · link ~10s |
| 02 foundation | **~9m** | PR verify lanes 3m29s · main convergence 3m56s |
| 03 infrastructure | **~10m** | main convergence 6m47s — Supabase project creation is the long pole |
| 04 workers | **~31m** | PR deploy lanes ~7m · strip-landing convergence 13m18s · restore convergence 10m54s |
| 05 edge | **5m22s** | apply→land→converge→`/health` probes, end to end |
| 06 console | **15m37s** | console builds are heavy; convergence needed all 3 auto-resumes (self-healed) |
| **total** | **~73m measured** | ~40m projected with `--no-wait` on 04–06 (item 1 below) |

## Improvements, in impact order

1. **Stop deploying twice — SHIPPED.** Every phase now lands with
   `land-pr.sh --no-wait` (phases 02–06; 03 already had it): one
   convergence per landing, the converge step is the gate. Projected total
   **~40m**. Rationale: the phase content comes from the PINNED baseline,
   already verified there; PR lanes deployed the fleet a second (and, for
   04's restore, a third) time. The check-gated `land-pr.sh` default
   remains for incremental changes on live products (`flows/batch.sh`).
2. **Optionally split phase 03** into `03a` (cloudflare-kv + supabase) and
   `03b` (db-migrate + hyperdrive) if green PR gates are preferred over
   `--no-wait`: 03b's plan lanes need supabase's job-output secrets, which
   exist only after 03a's merge applies. Both designs converge identically;
   `--no-wait` is landed, the split is the check-friendly alternative.
3. **Supabase project creation (~5–7m) is irreducible** from our side —
   budget for it; nothing to engineer around short of pre-provisioning
   projects.
4. **Watch GitHub Actions billing.** A full bootstrap is thousands of
   runner-minutes with double-deploys (hundreds without). A tripped
   spending limit presents as lanes that "fail" with NO logs anywhere —
   the message lives only in the check-run ANNOTATIONS
   (`gh api repos/<o>/<r>/check-runs/<job-id>/annotations`).
5. **Mint `ORUN_TOKEN` per phase** — it is short-lived (~30m). The
   container contract in BOOTSTRAP.md §3c covers this; a longer-lived
   bootstrap-scoped grant would remove the ceremony.

## Defects this run found and fixed (already landed — listed so nobody re-hits them)

| fix | what broke on a fresh fork |
|---|---|
| #50 | `secret://` refs: segment 1 is the WORKSPACE — the repo-slug rebrand rewrote both segments; every resolve failed `Validation failed` |
| #52 | `cloud check` passes without the LOCAL link cache (fresh HOME) — preflight now links unconditionally |
| #53 | the workspace-slug self-heal dirtied the tree before its own clean-tree check |
| #54 | later phases branded fresh baseline content with the product's scaffold-era rebrand copy — tool now always runs from the pinned baseline |
| #55 | supabase `adopt.tf` read `SUPABASE_ORG_ID`, but the job env carries `TF_VAR_supabaseOrgId` |
| #56/#57 | phase 03's PR lanes are structurally red on first boot → `--no-wait` landing |

## Second measured run — ambient (2026-08-02, workspace-scoped token)

Fully headless again, but with a **workspace-scoped `sk_` API token**
instead of a user session — the first run to exercise that credential
class. Clean-path times (with every fix this run produced landed,
baseline-v8 + orun v2.52.4):

| phase | time | notes |
|---|---|---|
| 02 foundation | **5m08s** | vs ~9m on vela |
| 03 infrastructure | **~15m** | apply/land ~2m · convergence ~11m (Supabase long pole) · verify |
| 04 workers | **20m49s** | vs ~31m on vela (single-deploy landings) |
| 05 edge | **5m03s** | |
| 06 console | **14m01s** | convergence needed 0 resumes |
| **total 02–06** | **~60m clean** | the run itself took longer — it surfaced and fixed 6 real defects |

What the workspace-token path surfaced (all fixed during the run):

1. `sk_` tokens see NO memberships list → slug resolution needs
   `orun workspace <ws>` (v2.52.1) — the direct org read.
2. `sk_` tokens cannot write repo links → the intent must declare
   `project:` (scaffold writes it; preflight self-heals, baseline-v5).
3. Intent declares the project SLUG; config-surface AND state routes take
   `prj_…` ids → CLI-side slug resolution (v2.52.2 secrets, v2.52.4 run).
   The lane pin in ci.yml must be ≥ v2.52.4.
4. Step `timeout:` didn't kill grandchildren — a wedged git held the
   step's pipes past its deadline (15m declared, 71m observed) → process-
   group kill + WaitDelay (orun v2.52.3).
5. git has NO transfer timeout → `http.lowSpeedLimit/Time` on every flow
   git (baseline-v6).
6. git's credential `store` fires EVERY configured helper (system
   osxkeychain included) → in a keychain-less HOME securityd can raise a
   BLOCKING dialog on the console user's screen, hanging the step until a
   human clicks. Get-only credential helper everywhere (baseline-v8).

Also: a converge that follows a commit touching NO components plans zero
lanes and reads "green" — the phase verify step is the real gate (it
caught exactly this); never trust a green run without it.
