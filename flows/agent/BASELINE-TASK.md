# Build the Lumen baseline

(Fetched by the platform at the pinned tag; {{WS}} {{ORG}} {{REPO}} {{TAG}}
are filled before delivery.)

You are building a product baseline into `{{ORG}}/{{REPO}}` for workspace
`{{WS}}`. A pre-built, idempotent build does all the work. Your job is to
ask three questions, start the build, relay what it prints, and report the
result.

The environment is already prepared: the repository is cloned, the
credentials are in place, and the tools are installed. Do not check,
install, configure, export or fix anything yourself. Do not read token
files. Do not run git, gh, or deploy commands. The build does all of it and
tells you if anything is missing.

## 1. Ask, then confirm

Ask the operator these three things in ONE message, using the question tool:

1. Product display name (for example "Acme Cloud")
2. Product domain (for example acme.dev; no DNS zone is needed yet)
3. workers.dev subdomain (for example acme)

When they answer, reply with one line confirming the three values, then
start the build. Do not wait for a second confirmation. If nobody answers
in 30 minutes, remind them once; after two hours, say you are still
waiting and stop.

## 2. Start the build

Run exactly this, in the background, and watch its output until it exits:

```bash
orun workflow run 'github:sourceplane/lumen@{{TAG}}//flows/agent/workflow.yaml' \
  --set productname="<display name>" --set productdomain=<domain> --set subdomain=<subdomain>
```

Substitute the three values from the intake. Change nothing else.

## 3. Relay the build's messages

The build prints four kinds of line. Post each one as it appears, in plain
words, without the prefix:

- `UPDATE: …` — post it. If ten minutes pass with no new line, post a short
  note that the current phase is still running and roughly how long it
  usually takes.
- `ACTION REQUIRED: …` — post it word for word and wait for the operator.
  When they say it is done, run the same build command again. Finished
  phases are skipped, so re-running is safe and quick.
- `FAILED: …` — post it together with the last 30 lines of output above it.
  Then run the same build command again once. If it fails at the same
  place a second time, stop and wait for the operator.
- `DONE` — post the summary block printed after it, then say the build is
  complete.

Never edit the product's code, infrastructure or CI to get past an error,
and never re-run more than once without hearing from the operator.

## Rules

- Never print a credential, token or key, even a partial one.
- Report only what the build printed. If you are unsure, say so.
- Expect about 75 minutes end to end.
