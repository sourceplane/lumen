# flows/ — the bootstrap and operations workflows

Everything here runs FROM this baseline checkout (or by remote reference —
see [BOOTSTRAP.md §2](../BOOTSTRAP.md)) and operates ON a product repo.
Products do not carry this directory: phases fetch the baseline themselves
at the pinned commit and apply into the product.

| path | what |
|---|---|
| [`phases/`](phases/README.md) | THE bootstrap: eight self-contained workflows (scaffold → foundation → infrastructure → workers → edge → console → optional domain → docs), each `apply → land → converge → verify`, all idempotent |
| `common/` | shared building blocks the phases compose: `ctx.sh` (product resolve/clone), `preflight.sh` (workspace readiness + self-heals), `apply-blueprint.sh` (slice apply + rebrand + slug resolution), `land-pr.sh` / `push-main.sh` (landings), `converge.sh` (watch + auto-resume ×3), `check-subdomain.sh` (validate the workers.dev subdomain input), `umbrella.sh` (phase checkpoint + resume probes), `redeploy-marker.sh` (force components into the `--changed` set), `verify-endpoints.sh`, `create-secrets.sh` (brokered provider secrets), `render-deployment-docs.sh` (phase 08's renderer) |
| [`AGENT-PROMPT.md`](AGENT-PROMPT.md) | the copy-paste runbook for handing a bootstrap to a (low-capability) agent — placeholders, prerequisites, exact commands, real failure signatures |
| [`testing/`](testing/) | testing-only provisioning (workspace + integrations + repo from tokens) — never part of bootstrapping |

The single-run express flow and the manual forking path were removed —
the phased bootstrap is the one supported flow (history has them if ever
needed).
