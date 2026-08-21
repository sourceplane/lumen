# Architecture

Two Jest suites, no runtime dependencies, no network. It walks `apps/*`, reads
the first of `wrangler.template.jsonc` or `wrangler.jsonc` it finds per app,
strips line comments and the deploy-time `@@wiring(...)@@` placeholders, and
asserts over the parsed objects.

Reading the **template** rather than the rendered config is deliberate: the
template is what is committed and reviewed, and the rendered `wrangler.jsonc`
is gitignored for workers that carry resource IDs. An assertion against the
rendered file would be an assertion against a build artifact that does not
exist on a clean checkout.

The suite deliberately asserts on named lists rather than counts. A failure
that reads `["integrations-worker: * * * * *", ...]` tells the reader which
jobs are competing for the budget; a failure that reads `expected 6 to be at
most 5` does not.

## secret-scoping.test.ts

Walks `apps/*` and `infra/*` for `component.yaml`, and collects every
`secretEnv` / `optionalSecretEnv` block tagged with the indentation it was
declared at — 2 spaces means component-level (attached to every environment),
8 means inside a `subscribe.environments[]` item.

Line-oriented rather than a YAML parse, deliberately: these files are
hand-written in one consistent style, and a guard whose whole value is being
cheap enough to always run should not pull a parser in to read four keys.

The two failure shapes it encodes were both established empirically against
`orun plan`, not inferred: a component-level ref reaches every environment, and
a per-environment `optionalSecretEnv` is dropped without a warning.
