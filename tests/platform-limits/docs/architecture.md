# Architecture

One Jest suite, no runtime dependencies, no network. It walks `apps/*`, reads
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
