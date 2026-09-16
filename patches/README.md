# Patch notes

One document per core patch this fork carries, named `NNNN-short-slug.md`.

A core patch is any change to upstream-owned files (`core/`, `scene/`, `servers/`,
`editor/`, `modules/`). Code in a module or GDExtension does not need an entry, because it
does not conflict on rebase and does not need re-deriving when Godot moves.

**Write the entry in the same commit as the patch.** The audience is whoever hits a
conflict in these hunks during a rebase six months from now, possibly on a Godot version
where the surrounding code has moved. They need to know what the patch is protecting
against and what it would take to re-derive it, not just what the diff says.

Each entry should cover:

- **What** the patch changes, file by file.
- **Why** — the failure it prevents, concretely enough to recognize a regression.
- **How** it works, including invariants a future edit could silently break.
- **Rejected alternatives**, so nobody re-litigates a dead end.
- **Upstream status** — issue/PR links, whether a fix is expected to land.
- **Verification** — what was actually tested, and what was not.
- **Conflict guidance** — what to check if the surrounding upstream code changes.

| Patch | Summary | Upstream |
| --- | --- | --- |
| [0001](0001-csharp-gchandle-race.md) | C# gchandle race: abort or silent data loss when the resource cache revives a collected wrapper | [#83762](https://github.com/godotengine/godot/issues/83762), [#112067](https://github.com/godotengine/godot/issues/112067) — both open |
