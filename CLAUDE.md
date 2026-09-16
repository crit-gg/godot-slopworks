# godot-slopworks

A fork of [godotengine/godot](https://github.com/godotengine/godot), maintained as a
**patch series pinned to an upstream release tag**. The entire workflow below exists to
keep `git diff 4.7.2-stable...slop-4.7.2` small, readable, and portable to the next Godot
release.

The base is a tag, not a branch. `4.7.2-stable` never moves, so what we build today is
what we build in six months — the fork's own commits are the only thing that changes
under us. Moving to a newer Godot is a deliberate act that creates a new branch off a
new tag, never a rebase that shifts the ground beneath an existing one.

## Branch rules

- **All work goes on `slop-4.7.2`.** It is rooted at the `4.7.2-stable` tag and is the
  fork's release line.
- **Never commit to a mirror branch.** `4.7`, `4.6`, `master`, `3.x`, and every other
  version-named branch are byte-identical mirrors of upstream. They are refreshed with
  `git push origin upstream/4.7:4.7`, never by committing.
- **`slop-4.7` is dormant, not current.** It was the old rolling line tracking
  `upstream/4.7`. It is kept for reference only; do not land new work there.
- **Never give `slop-4.7.2` an upstream tracking branch.** `pull.rebase=true` is set
  repo-locally, so configuring `branch.slop-4.7.2.merge=refs/heads/4.7` would make a
  stray `git pull` silently rebase the release line onto moving upstream code. With no
  tracking configured, `git pull` fails loudly instead. That is the desired behavior.
  When the branch is published, `git push -u origin slop-4.7.2` is the correct setup —
  it tracks `origin`, never `upstream`.
- **Never push to `upstream`.** Its push URL is deliberately set to
  `DISABLED_read_only`. Do not repair it.

## Commit rules

- **Prefix every commit `[slop]`.** `git log --oneline 4.7.2-stable..slop-4.7.2` is the
  authoritative inventory of what this fork owns; the prefix keeps it scannable once
  cherry-picks onto a future tag interleave our dates with upstream's.
- **One logical change per commit.** The series is replayed onto a new tag on every
  Godot release. Small, self-contained commits are the difference between a five-second
  conflict resolution and an archaeology session.
- **Do not squash unrelated patches together.** Each should be independently revertable
  and independently portable to the next release branch.

## Where new code goes

Prefer, in this order, and justify any move down the list:

1. **GDExtension** — zero engine changes, survives version bumps.
2. **Custom module**, either in-tree at `modules/slopworks/` or out-of-tree via
   `scons custom_modules=/path/to/repo` (see `SConstruct`). New files never conflict.
3. **Core patches** to `scene/`, `servers/`, `editor/`, `core/` — the only category that
   costs anything when moving to a new release.

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

This matters more than it looks, and more than it did on a pre-release base. `version.py`
at `4.7.2-stable` reads `status = "stable"`, and the managed packages are versioned from
the engine version, so an unmarked local build produces `Godot.NET.Sdk 4.7.2` — the exact
package ID and version Godot actually shipped — and drops it into `~/.nuget/packages`,
where it shadows the official release for **every** project on this machine. There is no
`-rc` suffix left to tell the two apart. Our builds identify as `4.7.2-slopworks`.

The status is set via env var rather than by editing `version.py`, deliberately:
`version.py` is rewritten on every upstream release, so patching it would guarantee a
conflict every time the series is replayed onto a new tag.

## Documenting patches

Every core patch gets an entry in `patches/`, written **in the same commit as the patch
itself**. See `patches/README.md` for the format and what each entry must cover.

The audience is whoever hits a conflict in those hunks while moving the series to a
future Godot release, where the surrounding code may have moved. Record what the patch
protects against, the invariants a future edit could silently break, and the alternatives
already ruled out — a diff alone does not carry any of that.

Entries are also where upstream status lives. If upstream lands its own fix for something
we patched, **drop our patch rather than merging it**; note that in the entry.

## Tracking upstream

The release line does not follow upstream. Fetching is safe and useful — it is how you
see what landed and whether a patch we carry has been fixed upstream:

```sh
git fetch upstream --prune --tags
git log --oneline 4.7.2-stable..upstream/4.7    # what upstream has done since our base
git push origin upstream/4.7:4.7                # refresh the mirror (optional)
```

**Do not rebase `slop-4.7.2` onto `upstream/4.7`.** Picking up upstream's post-4.7.2 work
means moving to its next release tag, which is the procedure below.

## Moving to a new Godot release

```sh
git fetch upstream --tags
git switch -c slop-4.7.3 4.7.3-stable
git cherry-pick 4.7.2-stable..slop-4.7.2
```

The cherry-pick range works because the series is rooted directly at the tag, so every
commit after `4.7.2-stable` is ours. `rerere` is enabled repo-locally, so conflict
resolutions replay automatically if the same hunks conflict again on a later release.
Resolve a conflict carefully the first time.

The old branch is left in place rather than deleted — it is the record of what we shipped
on that Godot version. Anything living in a GDExtension or custom module ports for free;
only core patches need review, and `patches/` says what each one is defending.

## Agent rules

- **Do not run `git push`, `git push --force`, or rewrite published history without
  explicit confirmation.** Rebasing local commits is fine; publishing them is not.
- **Do not commit to a mirror branch under any circumstances**, including "just to test".
- **Do not move the release line to a new upstream base on your own initiative.**
  Fetching is fine; cherry-picking the series onto a new tag changes what the user is
  building against and is their call.
- Before editing an upstream-owned file, check whether the change can be made in a module
  or GDExtension instead, and say so if it can.
