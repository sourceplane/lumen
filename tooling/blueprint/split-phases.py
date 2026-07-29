#!/usr/bin/env python3
"""Derive one blueprint per phase from a phased monolithic Blueprint.

  Usage:  python3 tooling/blueprint/split-phases.py repo-blueprint.yaml flows/phases

  Regenerate the phase blueprints after editing repo-blueprint.yaml (the
  baseline as a Blueprint of itself). Known phase names are written to
  flows/phases/<NN-folder>/blueprint.yaml, co-located with each phase's
  workflow and README.

Why this is not just a file split:

  * `dependsOn` an undeclared module is a hard validation error
    (internal/scaffold/blueprint.go:290), so every cross-phase edge must be
    pruned. That is safe precisely BECAUSE the phases are run in order — the
    barrier the monolith enforced declaratively becomes the run sequence.
  * Hooks need the complete tree (rebrand enumerates via `git ls-files`), so
    only the final phase carries `hooks.postInstantiate`.
  * `inputs`, `sources` and `ignore` are replicated verbatim into every phase:
    each run resolves the baseline independently and must ignore the same
    build artifacts.
"""
import sys, yaml, pathlib, os

src = pathlib.Path(sys.argv[1])
outdir = pathlib.Path(sys.argv[2])
bp = yaml.safe_load(src.read_text())

# A `kind: dir` source path is resolved relative to the BLUEPRINT's own
# directory, not the cwd. The split files live somewhere else, so every dir
# source has to be re-based or `path: .` would point at the blueprints folder.
src_dir = src.resolve().parent


def rebased_sources(dest_dir):
    """Sources with `kind: dir` paths re-based to dest_dir.

    A dir source path resolves relative to the BLUEPRINT FILE's own
    directory. Phase blueprints land in flows/phases/<folder>/, one level
    deeper than the outdir given on the command line, so the rebase is
    computed per phase against the file's own parent — computing it against
    outdir would be off by exactly one level and silently point the source
    at the wrong tree.
    """
    out = []
    for s in bp.get("sources", []):
        s = dict(s)
        if s.get("kind") == "dir" and "path" in s:
            target = (src_dir / s["path"]).resolve()
            s["path"] = os.path.relpath(target, dest_dir.resolve())
        out.append(s)
    return out


phases = bp.get("phases") or []
if not phases:
    sys.exit("blueprint declares no phases — nothing to split")

by_name = {m["name"]: m for m in bp["modules"]}
outdir.mkdir(parents=True, exist_ok=True)

written = []
for i, ph in enumerate(phases, start=1):
    members = list(ph["modules"])
    member_set = set(members)
    missing = [m for m in members if m not in by_name]
    if missing:
        sys.exit(f"phase {ph['name']} names unknown module(s): {missing}")

    mods = []
    pruned = 0
    for name in members:
        m = dict(by_name[name])
        if "dependsOn" in m:
            keep = [d for d in m["dependsOn"] if d in member_set]
            pruned += len(m["dependsOn"]) - len(keep)
            if keep:
                m["dependsOn"] = keep
            else:
                m.pop("dependsOn")
        mods.append(m)

    doc = {
        "apiVersion": bp["apiVersion"],
        "kind": bp["kind"],
        "metadata": {
            "name": f"{bp['metadata']['name']}-{ph['name']}",
            "description": (
                f"Phase {i}/{len(phases)} ({ph['name']}) of {bp['metadata']['name']}. "
                f"Cross-phase dependsOn edges are pruned; ordering is enforced by "
                f"running the phases in sequence into the same --out."
            ),
        },
        "inputs": bp.get("inputs", {}),
        "sources": None,  # filled below, once the output path is known
        "ignore": bp.get("ignore", []),
        "modules": mods,
        "phases": [{"name": ph["name"], "modules": members}],
    }
    # Hooks run against a complete tree, so they belong to the last phase only.
    if i == len(phases) and bp.get("hooks"):
        doc["hooks"] = bp["hooks"]

    # Phase folders under flows/phases/ are named by EXECUTION order (the
    # workspace/root phase runs FIRST there, as "01-scaffold"), while this
    # split enumerates BLUEPRINT order. Map known phase names to their
    # folders; unknown names fall back to flat NN-name.yaml in outdir.
    PHASE_FOLDERS = {
        "workspace": "01-scaffold",
        "foundation": "02-foundation",
        "infrastructure": "03-infrastructure",
        "workers": "04-workers",
        "edge": "05-edge",
        "console": "06-console",
        "domain": "07-domain",
    }
    folder = PHASE_FOLDERS.get(ph["name"])
    if folder:
        path = outdir / folder / "blueprint.yaml"
        path.parent.mkdir(parents=True, exist_ok=True)
    else:
        path = outdir / f"{i:02d}-{ph['name']}.yaml"
    doc["sources"] = rebased_sources(path.parent)
    path.write_text(yaml.safe_dump(doc, sort_keys=False, width=100))
    written.append((str(path.relative_to(outdir)), len(mods), pruned, "hooks" if "hooks" in doc else "-"))

w = max(len(n) for n, *_ in written)
print(f"{'file'.ljust(w)}  modules  pruned-edges  hooks")
for n, c, p, h in written:
    print(f"{n.ljust(w)}  {c:>7}  {p:>12}  {h}")
print(f"\n{len(written)} phase blueprint(s) → {outdir}")
print("dir sources re-based per phase folder")
