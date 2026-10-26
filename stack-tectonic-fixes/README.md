# stack-tectonic-fixes — one composition, patched until upstream ships the fix

This directory exists to be deleted. It holds a single composition,
`turbo-package`, copied from the published stack-tectonic **0.20.0** with a
three-token fix, and `intent.yaml` binds that one composition type to it. Every
other composition still comes from the pinned OCI artifact.

## What is wrong upstream

0.20.0's `jobs/turbo-package-verify.yaml` guards each optional step on a key
the job's template context does not have:

```
{{if .preBuildCommand}}            ← orun's context has no top-level parameters
{{.parameters.preBuildCommand}}    ← the value is here
{{else}}
echo "Skipping pre-build."
```

orun gives a job template three namespaces — `.orun`, `.parameters` and
`.env` — so `.preBuildCommand` is always empty, and **pre-build skips itself
on every component, whatever the component declares**. In this repository
that is every test suite: their tests are their `preBuildCommand`. `build` and
`typecheck` have the same mistake and only appear to work, because their
`else` defaults are the commands every component here declares anyway.

The fix is `.<key>` → `.parameters.<key>` in those three guards, and nothing
else. `upstream-0.20.0.sha256` records the published files. The baseline this
repository was built from has a contract test that reverses the three fixes
and requires the result to hash to exactly those files, so the copy a product
receives is the published one plus the fix. To check it here:

```
sed -e 's/if \.parameters\.\(preBuildCommand\|buildCommand\|typecheckCommand\)}}/if .\1}}/' \
  compositions/turbo-package/jobs/turbo-package-verify.yaml | sha256sum
```

prints the `jobs/turbo-package-verify.yaml` line of `upstream-0.20.0.sha256`,
and every other file hashes as recorded.

## Deleting it

When a stack-tectonic release reads `.parameters.*` in those guards:

1. bump the pin in `intent.yaml` (`compositions.sources`, `stack-tectonic`);
2. delete the `stack-tectonic-fixes` source and the `turbo-package` binding
   beside it;
3. delete this directory — and, in the baseline, its module in
   `repo-blueprint.yaml`.

The baseline's contract test fails on any pin other than 0.20.0 while this
directory exists, so moving the pin is the moment somebody has to decide.
