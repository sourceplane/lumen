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
