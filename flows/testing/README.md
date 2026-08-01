# flows/testing — throwaway provisioning, TESTING ONLY

**Nothing in this folder is part of the bootstrap or scaffold path.** Do not
reference it from BOOTSTRAP.md, `flows/phases/`, or the express flow. Real
products get their workspace and provider consents deliberately, by a human,
in the console; these flows exist so bootstrap RUNS can be exercised
end-to-end (CI-style, containers, soak tests) without console clicks.

## provision-workspace.yaml

Creates the full throwaway prerequisite set in one run:

1. **workspace** — `orun cloud workspace create` (prints and records the
   `org_…` id; the id feeds `--set workspace=…` of the phase workflows —
   verified to resolve everywhere the flows use it),
2. **cloudflare connection** — token-paste connect from
   `$CLOUDFLARE_API_TOKEN`,
3. **supabase connection** — personal-access-token connect (IH6, `sbp_…`)
   from `$SUPABASE_PAT`,
4. **repo** (optional) — an empty private test repo.

Provider tokens travel ONLY via environment variables into the connect
verbs' stdin — never as workflow inputs, so they cannot land in argv, logs,
or run state.

```bash
CLOUDFLARE_API_TOKEN=… SUPABASE_PAT=… \
orun workflow run flows/testing/provision-workspace.yaml \
  --set name=scratch-2026-07 --set reponame=scratch-product
```

Requires orun ≥ v2.51.0 (`cloud workspace create`, `integrations <provider>
connect`), an authenticated orun session (or `ORUN_TOKEN`), and gh (or
`GITHUB_TOKEN`).

Cleanup is manual and YOUR job: delete the test repo, disconnect the
integrations, and retire the workspace when done — this flow only creates.
