# godot-slopworks

A fork of [godotengine/godot](https://github.com/godotengine/godot), maintained as a
**rebased patch series** on top of an upstream release branch. The entire workflow below
exists to keep `git diff upstream/4.7...slop-4.7` small, readable, and portable to the
next Godot version.

## Branch rules

- **Never commit to a mirror branch.** `4.7`, `4.6`, `master`, `3.x`, and every other
  version-named branch are byte-identical mirrors of upstream. They are refreshed with
  `git push origin upstream/4.7:4.7`, never by committing.
- **All work goes on `slop-4.7`.** It tracks `upstream/4.7` for pulls and pushes to
  `origin`. If you find yourself on a mirror branch with local changes, stop and move
  them to `slop-4.7` before committing.
- **Never push to `upstream`.** Its push URL is deliberately set to
  `DISABLED_read_only`. Do not repair it.

## Commit rules

- **Prefix every commit `[slop]`.** `git log --oneline upstream/4.7..slop-4.7` is the
  authoritative inventory of what this fork owns; the prefix keeps it scannable after a
  rebase interleaves dates with upstream's.
- **One logical change per commit.** A patch series is rebased dozens of times over its
  life. Small, self-contained commits are the difference between a five-second conflict
  resolution and an archaeology session.
- **Do not squash unrelated patches together.** Each should be independently revertable
  and independently portable to the next version branch.

## Where new code goes

Prefer, in this order, and justify any move down the list:

1. **GDExtension** — zero engine changes, survives version bumps.
2. **Custom module**, either in-tree at `modules/slopworks/` or out-of-tree via
   `scons custom_modules=/path/to/repo` (see `SConstruct`). New files never conflict.
3. **Core patches** to `scene/`, `servers/`, `editor/`, `core/` — the only category that
   costs anything at rebase time.

The fork currently carries **core patches only**; no module scaffolding exists yet. That
is a deliberate starting point, not a permanent one. **If the core diff starts sprawling,
raise moving it into a module rather than letting the diff grow.**

When a core patch is unavoidable, keep it minimal and localized:

- Prefer adding a new file over editing an upstream one.
- Prefer appending to the end of a function or list over editing the middle of one.
- Keep hunks tight — do not reformat, reorder, or "clean up" surrounding upstream code,
  as every touched line is a line that can conflict forever after.

## Building

**Always build through `./build.sh`, never bare `scons`.** It sets
`GODOT_VERSION_STATUS=slopworks`, which is what keeps our builds and our GodotSharp NuGet
packages from claiming the version and package IDs upstream Godot publishes.

This matters more than it looks. The managed packages are versioned from the engine version,
so an unmarked local build produces e.g. `Godot.NET.Sdk 4.7.3-rc` and drops it into
`~/.nuget/packages`, where it shadows the official package of that version for **every**
project on the machine. Our builds identify as `4.7.3-slopworks`.

The status is set via env var rather than by editing `version.py`, deliberately: `version.py`
changes on every upstream patch bump, so patching it would guarantee a conflict on every
single rebase.

## Documenting patches

Every core patch gets an entry in `patches/`, written **in the same commit as the patch
itself**. See `patches/README.md` for the format and what each entry must cover.

The audience is whoever hits a conflict in those hunks during a future rebase, possibly on a
Godot version where the surrounding code has moved. Record what the patch protects against,
the invariants a future edit could silently break, and the alternatives already ruled out —
a diff alone does not carry any of that.

Entries are also where upstream status lives. If upstream lands its own fix for something we
patched, **drop our patch rather than merging it**; note that in the entry.

## Updating from upstream

```sh
git fetch upstream --prune
git pull                            # rebases slop-4.7 onto upstream/4.7
git push --force-with-lease         # never plain --force
git push origin upstream/4.7:4.7    # refresh the mirror
```

`rerere` is enabled repo-locally, so conflict resolutions replay automatically on
subsequent rebases. Resolve a conflict carefully the first time; you are resolving it
for every future rebase.

Use `--force-with-lease`, never `--force`: it refuses the push if someone else has
advanced `origin/slop-4.7` since your last fetch.

## Moving to a new Godot version

```sh
git fetch upstream 4.8
git switch -c slop-4.8 upstream/4.8
git cherry-pick <first-slop-commit>..slop-4.7
```

Anything living in a GDExtension or custom module ports for free; only core patches
need review.

## Agent rules

- **Do not run `git push`, `git push --force`, or rewrite published history without
  explicit confirmation.** Rebasing local commits is fine; publishing them is not.
- **Do not commit to a mirror branch under any circumstances**, including "just to test".
- **Do not upstream-sync on your own initiative.** Fetching is fine; rebasing the working
  branch changes what the user is building against and is their call.
- Before editing an upstream-owned file, check whether the change can be made in a module
  or GDExtension instead, and say so if it can.
