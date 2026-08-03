# Agent runbook — bootstrap a product from this baseline

Copy everything below the line into the agent's task prompt, replacing the
FIVE placeholders: `<REPO>` (product repo slug, e.g. `atlas`),
`<WS>` (workspace id, e.g. `ws_ABCD1234`), `<PRODUCT_NAME>`,
`<PRODUCT_DOMAIN>`, `<SUBDOMAIN>` (workers.dev subdomain), plus the two
credentials. Pin `@<TAG>` to the baseline tag you are bootstrapping from.

Operator prerequisites (do these BEFORE handing off — the agent cannot):
1. Workspace exists; GitHub + Cloudflare + Supabase integrations ACTIVE.
2. **An ADMIN-role API key** for the workspace (builder/viewer keys read
   fine but secret writes are denied, masked as `not_found`).
3. **The product repo allow-listed** in the workspace (console →
   Settings → Git repos) — the one console action tokens cannot self-heal.
4. A GitHub token: fine-grained PAT with read on `sourceplane/lumen`; on
   the product repo: contents write, pull-requests write, actions
   read+write, checks read. (Classic PATs additionally need `workflow`
   scope.) If the environment substitutes its own GitHub credential
   (some sandboxes do), landings and convergence fall back to plain REST
   automatically; if even REST Actions is blocked, phases accept
   `--set watch=false` — then verify runs out-of-band.

---

# Task: bootstrap the product "<REPO>" — fully headless

You are bootstrapping a new SaaS product into `sourceplane/<REPO>` and the
Orun workspace `<WS>` by running pre-built workflows IN ORDER. Every
workflow is idempotent: re-running a completed or FAILED one is always
safe — the flows self-heal their own crash debris.

## Rules
- Run commands EXACTLY as written, one at a time, in the same shell.
- Phase success = exit 0 AND the final line says `succeeded`.
- If a phase fails: read the last 20 lines — the flows print ACTIONABLE
  messages (several name the exact console step or fix). If the message
  names an operator action, report it and wait. Otherwise re-run the same
  command once; if it fails again, stop and report the last 30 lines.
- Never print the values of ORUN_TOKEN or GITHUB_TOKEN.
- If your shell does not persist environment between commands, re-export
  the three variables before every command (that is fine — "never in
  files" is the rule, not "export only once").

## Step 0 — prerequisites

Check the tools (install what is missing):

```bash
git --version && node --version && python3 --version && curl --version | head -1
gh --version || echo "MISSING: install gh — https://github.com/cli/cli/releases (or apt/brew)"
orun --version || echo "MISSING: orun"
```

Note the exact spelling: `orun --version` (there is no `orun version`
subcommand on older CLIs). Install orun v2.52.6+ if missing or older:

```bash
OS=$(uname -s | tr '[:upper:]' '[:lower:]'); ARCH=$(uname -m); [ "$ARCH" = x86_64 ] && ARCH=amd64; [ "$ARCH" = aarch64 ] && ARCH=arm64
curl -fsSL "https://github.com/sourceplane/orun/releases/download/v2.52.6/orun_2.52.6_${OS}_${ARCH}.tar.gz" | tar xz
sudo mv orun /usr/local/bin/ 2>/dev/null || { mkdir -p ~/bin && mv orun ~/bin/ && export PATH="$HOME/bin:$PATH"; }
orun --version
```

## Step 1 — credentials

```bash
export ORUN_TOKEN='<ADMIN-ROLE sk_ KEY>'
export GITHUB_TOKEN='<GITHUB TOKEN>'
export GH_TOKEN="$GITHUB_TOKEN"
```

## Step 2 — working directory

```bash
mkdir -p ~/bootstrap-<REPO> && cd ~/bootstrap-<REPO>
```

Stay here for every phase (they share `baseline/` and `product/`).

## Step 3 — run the umbrella (preferred: one command does everything)

```bash
orun workflow run 'github:sourceplane/lumen@<TAG>//flows/phases/00-all/workflow.yaml' \
  --set workspace=<WS> --set reponame=<REPO> \
  --set productname="<PRODUCT_NAME>" --set productdomain=<PRODUCT_DOMAIN> \
  --set subdomain=<SUBDOMAIN>
```

It retries each phase itself, probes the credential's write access in
minute two, and ends with an independent verification. Expect 60–75
minutes; the output names the exact operator action if it stops. If it
completes, skip to Step 4. Use the per-phase commands below ONLY if the
operator asks for phase-at-a-time control.

## Step 3-alt — the phases, one at a time

Notes that prevent confusion:
- Phase 01's scaffold is the repo's FIRST commit and lands **directly on
  `main`** (an empty repo cannot take a PR) — this is by design. The flow
  pins `main` as the default branch itself.
- Supabase project creation in phase 03 takes 5–10 minutes per
  environment. That is normal; do not interrupt.
- Phase 04 performs TWO landings with a convergence between them. Let it
  run to completion.

```bash
orun workflow run 'github:sourceplane/lumen@<TAG>//flows/phases/01-scaffold/workflow.yaml' \
  --set workspace=<WS> --set reponame=<REPO> \
  --set productname="<PRODUCT_NAME>" --set productdomain=<PRODUCT_DOMAIN> \
  --set subdomain=<SUBDOMAIN>

orun workflow run 'github:sourceplane/lumen@<TAG>//flows/phases/02-foundation/workflow.yaml' \
  --set workspace=<WS> --set repo=sourceplane/<REPO>

orun workflow run 'github:sourceplane/lumen@<TAG>//flows/phases/03-infrastructure/workflow.yaml' \
  --set workspace=<WS> --set repo=sourceplane/<REPO>

orun workflow run 'github:sourceplane/lumen@<TAG>//flows/phases/04-workers/workflow.yaml' \
  --set workspace=<WS> --set repo=sourceplane/<REPO>

orun workflow run 'github:sourceplane/lumen@<TAG>//flows/phases/05-edge/workflow.yaml' \
  --set workspace=<WS> --set repo=sourceplane/<REPO>

orun workflow run 'github:sourceplane/lumen@<TAG>//flows/phases/06-console/workflow.yaml' \
  --set workspace=<WS> --set repo=sourceplane/<REPO>

orun workflow run 'github:sourceplane/lumen@<TAG>//flows/phases/08-docs/workflow.yaml' \
  --set workspace=<WS> --set repo=sourceplane/<REPO>
```

(Phase 07 — custom domain — is skipped: it needs a Cloudflare zone.)

## Step 4 — final verification (all four must print 200)

```bash
for u in \
  "https://<REPO>-api-edge-stage.<SUBDOMAIN>.workers.dev/health" \
  "https://<REPO>-api-edge-prod.<SUBDOMAIN>.workers.dev/health" \
  "https://<REPO>-web-console-next-stage.<SUBDOMAIN>.workers.dev" \
  "https://<REPO>-web-console-next-prod.<SUBDOMAIN>.workers.dev"; do
  printf '%-70s %s\n' "$u" "$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 "$u")"
done
```

## Failure signatures you may actually hit

| signature | meaning → action |
|---|---|
| `repo not allow-listed for workspace …` | Operator must add the repo in console → Settings → Git repos. Report and wait, then re-run the phase. |
| Secret write fails `not_found` while listings worked | The API key role is below ADMIN. Operator must re-mint the key; report and wait. |
| `still missing ACTIVE connection(s) … after 10m` | Operator must connect that integration in the console. Report and wait. |
| `dirty tree left by a previous failed apply — resetting` | Normal self-heal after a crashed attempt; the run continues. |
| OCI resolve 503 / network error mid-apply | Transient. Re-run the same phase once. |
| A convergence lane fails once and the flow prints `↻ resuming failed lanes` | Normal — smoke races and lock races heal on resume. Keep waiting. |
| Lanes fail with NO logs at all | GitHub Actions billing/spending limit — message hides in check-run annotations. Stop and report. |
| `watch=false` needed (environment cannot see Actions even via REST) | Append `--set watch=false` to the phase, then verify the CI run out-of-band before the next phase. |

## Report back

Per phase: pass/fail and duration. Then the four URL results and the
contents of `product/ai/context/deployment.md`.
