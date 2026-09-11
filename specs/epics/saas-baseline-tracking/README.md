# Epic: saas-baseline-tracking (BT) — the Lumen port

**The bootstrap is work, so it lives where work lives.** The cross-repo
programme makes a baseline bootstrap author itself into the workspace's
task plane — one epic ("Infra baselining"), one milestone per phase, one
task per landing, every landing PR on an `orun/<KEY>-<phase>` branch so the
platform's observation drain folds each task to `done` from evidence alone.
Nothing is asserted; the ledger reads what the flows did.

The design, decisions and cross-repo plan live where the work was built
first: [`cirrus/specs/epics/saas-baseline-tracking/`](https://github.com/sourceplane/cirrus/tree/main/specs/epics/saas-baseline-tracking)
(umbrella), [`orun/specs/orun-baseline-tracking/`](https://github.com/sourceplane/orun/tree/main/specs/orun-baseline-tracking)
(the binary's CLI and MCP leg), and orun-cloud
`specs/epics/saas-baseline-tracking/` (the plane's MCP writes). This
folder records what was ported here and where Lumen differs.

## Status

| Field | Value |
|-------|-------|
| Status | ✅ **Ported** (BT1–BT5 + the BT6 CI tests, one PR) — the live rehearsal is the same human gate as in cirrus |
| Cluster | **BT** (port of cirrus BT1–BT6; depends on orun BT-O1–BT-O4, all merged on orun `main`) |
| Owner(s) | `flows/common/track.sh`, `land-pr.sh`, `push-main.sh`, `ghrest.sh`, `umbrella.sh`; every `flows/phases/*/workflow.yaml` + `task-contract*.yaml`; `flows/agent/BASELINE-TASK.md`, `flows/AGENT-PROMPT.md`; `flows/testing/`; `tests/flows` |
| Builds on | the same phased bootstrap cirrus inherited from here (`flows/phases`), plus Lumen's own checkpointed umbrella (`umbrella.sh`) |

## Where Lumen differs from the cirrus build

- **The umbrella is checkpointed.** `run_phase` lives in
  `flows/common/umbrella.sh` (resume by checkpoint + reality probes), so
  `track` / `epicslug` ride in as `UMB_TRACK` / `UMB_EPICSLUG` and every
  phase invocation carries them. The `programme` step runs before
  `scaffold` and is deliberately outside the checkpoint: it is cheap and
  idempotent, and a resumed run must see the same epic.
- **Phase 03 is Supabase + Hyperdrive.** Its milestone's exit criteria,
  its task contract (`cloudflare-kv`, `supabase`, `db-migrate`,
  `cloudflare-hyperdrive`) and the landing title follow Lumen's own phase.
- **Twelve workers** in the phase-04 contracts (cirrus lists ten).
- Everything else — `track.sh`'s verbs and degradation, the pen path in
  `land-pr.sh` (`Orun-Task` trailer, `Task:` + manifest body, label
  best-effort), `push-main.sh --task` always taking the pen, phase 01
  seeding `main` and landing the scaffold as PR #1 with the
  workflows-permission fallback, the brief's Step 1b / rollup updates /
  `orun spec push`, the contract tests and the `tests/flows` quick-check
  component — is byte-for-byte the cirrus build.

## Human gates (shared with cirrus)

- **The orun release and the flows' floor.** `BOOTSTRAP.md` and the
  prompts pin `orun ≥ v2.52.6`; the task-plane verbs and the pen flags
  are on orun `main`, not yet in a tag. Until the floor moves, a bootstrap
  on a released binary runs untracked (each landing says so once) — the
  pre-BT behaviour, byte-identical.
- **The rehearsal.** One real Lumen bootstrap with `track=true` whose epic
  rollup reads `8/8 done`, recorded here with the task keys.

## Agent brief v2 — one command, four kinds of line

Ported from cirrus (its #36). The brief is 65 lines: ask three questions,
run `flows/agent/workflow.yaml` with the three values, relay
`UPDATE:` / `ACTION REQUIRED:` / `FAILED:` / `DONE` lines, post the summary.
`flows/agent/build.sh` reads the workspace, repository, checkout and
credentials from the environment the platform prepared, checks the binary
floor, installs `gh` only if absent, runs the umbrella with tracking on and
composes the summary. The umbrella's `watch` defaults to `auto`
(`resolve_watch` in `flows/common/umbrella.sh`: CI on main → watch; no
workflow files → one `ACTION REQUIRED` naming the App's Workflows grant),
and `verify` attaches the deployment record to the epic. Contract test:
`flows/testing/agent-build.test.sh`.
