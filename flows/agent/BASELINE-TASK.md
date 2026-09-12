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

Ask the operator these three things in ONE ordinary message, as a numbered
list they can answer in one line. Do NOT use a multiple-choice or options
tool: these are free-text values only the operator knows, so a picker can
offer nothing but invented examples — and an operator who picks "custom"
hands you back no value at all, costing two more turns to undo (observed
live).

1. Product display name (for example "Acme Cloud")
2. Product domain (for example acme.dev; no DNS zone is needed yet)
3. workers.dev subdomain (for example acme)

Take the answer in whatever shape it arrives: "1. myproduct 2. myproduct.dev
3. orundemo" and three separate lines are the same answer. Ask again only
for a value that is genuinely missing, naming just that one.

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
  place a second time, say so in one message — what failed, and the file
  and line if the output named one — and stop. Do not offer to investigate,
  do not read the failing script, and do not run anything to find out more:
  a failure that repeats identically is a defect for the people who own the
  build, and the output you already posted is what they need. If the output
  points at a credential or an authorisation ("401", "invalid token", "not
  authorized"), say that the session's credential looks expired and that it
  needs an operator — do not probe it, and do not run `gh`, `git` or any
  other command to confirm.
- `DONE` — post the summary block printed after it, then say the build is
  complete.

Never edit the product's code, infrastructure or CI to get past an error,
and never re-run more than once without hearing from the operator.

## Rules

- Never print a credential, token or key, even a partial one.
- Report only what the build printed. If you are unsure, say so.
- Expect about 75 minutes end to end.
