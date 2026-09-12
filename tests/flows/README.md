# tests/flows — the bootstrap flows' contract tests

A quick-check component that runs the two contract tests under
`flows/testing/` in this repository's CI (saas-baseline-tracking BT6):

- `track.test.sh` — `flows/common/track.sh` over a fake `orun`: a first
  run creates epic + milestone + task, a second run creates nothing and
  prints the same handles, a second landing is a second task in the same
  milestone, an old binary degrades to "untracked" with one line.
- `land-pr.test.sh` — `flows/common/land-pr.sh` / `push-main.sh` over a
  fake pen and a fake `gh`, bare-repo remotes: a tracked landing goes
  through the pen (grammar branch, trailer, body, label, back on a pulled
  main), an untracked landing is the old path, a refused pen merges the
  `orun/…` branch directly, a bad suffix lands untracked, `push-main
  --task` takes the pen.

- `phase-vars.test.sh` — a static read of every phase workflow: no shell
  function may assign to a step's path handles (`out`, `L`, `P`, `W`,
  `slug`, `remote_url`), because functions share the step's variables and a
  rebind corrupts everything after it with no error where the mistake is.
  Phase 01's `push_main` assigned the git push transcript to `out`, the
  product repo directory, and `land-pr.sh "$out"` then ran `cd` on a
  transcript. Also checks that `land-pr.sh` refuses a non-directory first
  argument with a one-line diagnosis instead of a raw `cd` failure.

`bash`, `python3`, `git` — no network, no credential. Run locally with
`pnpm --filter @saas/flows-tests test` or the scripts directly. This
component is the baseline's own and never ships to a product.
