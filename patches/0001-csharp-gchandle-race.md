# 0001 — C# gchandle race on resource cache resurrection

**Applies to:** 4.7.x. Branched from the `4.7.2-stable` tag (`ed1daf0bf0`); originally
written against 4.7.3-rc and diagnosed on 4.7.1-stable-mono. The patch is byte-identical on
both bases - nothing between those two commits touches the files it changes.
**Upstream:** [#83762](https://github.com/godotengine/godot/issues/83762) (open, confirmed,
no milestone, no assignee, open since Oct 2023) and
[#112067](https://github.com/godotengine/godot/issues/112067) (open, same race on instance
bindings). [#75131](https://github.com/godotengine/godot/issues/75131) and
[#121018](https://github.com/godotengine/godot/issues/121018) are closed duplicates.
**Status:** local patch, not submitted upstream.

## The symptom

On the .NET finalizer thread, in a debug build:

```
ERROR: FATAL: Condition "gchandle.is_released()" is true.
   at: mono_object_disposed_baseref (modules/mono/csharp_script.cpp:1788)
```

`CRASH_COND` is a `ud2`, so the process takes SIGILL and the crash handler turns it into
SIGABRT. Any `/root propagate_notification` error after it is noise from the handler
sending `NOTIFICATION_CRASH` off the main thread.

In a **release** build `CRASH_COND` compiles out and there is no crash. This is worse, not
better: the resource comes back with **default exported values** instead of its authored
ones. The originally observed victim was a `SmoothPositionFollower` C# resource that came
back with `Lag` and `MaxLagDistance` at zero.

The sibling bug (#112067) surfaces on the managed side instead:

```
System.InvalidOperationException: Handle is not initialized.
   at System.Runtime.InteropServices.GCHandle.FromIntPtr(nint)
   at Godot.Bridge.ScriptManagerBridge.SwapGCHandleForType(...)
```

## Why it happens

A C# scripted `RefCounted` holds its managed wrapper through a `GCHandle`. The handle is
**strong** while the native side references the object, and is swapped to **weak** once the
managed wrapper is the only holder left (`CSharpInstance::refcount_decremented`), so the GC
is allowed to collect it.

The race, in order:

1. A resource falls to a single holder, so its handle is swapped strong → weak.
2. The .NET GC collects the managed wrapper. `GCHandle.Target` is now null, but the
   finalizer for that object has only been *queued*, not run.
3. Something loads a scene that references the resource by path.
   `ResourceCache::get_ref` (`core/io/resource.cpp`) finds the cache entry and constructs a
   `Ref` from it — **this is the resurrection**, and it happens before the cache mode is
   even consulted, so `CACHE_MODE_IGNORE` does not avoid it.
4. Constructing that `Ref` calls `CSharpInstance::refcount_incremented`, which tries to swap
   the weak handle back to a strong one. It nulls `gchandle.handle` first, then calls
   managed `SwapGCHandleForType`.
5. `SwapGCHandleForType` reads `oldGCHandle.Target`, finds null, frees the old handle and
   returns false. `refcount_incremented` returns early. **The instance is now left with a
   permanently released handle.**
6. The queued finalizer finally runs, reaches `mono_object_disposed_baseref`, and trips
   `CRASH_COND(gchandle.is_released())`.

Three distinct defects sit on that path, and the patch addresses all three.

## What the patch does

### Layer 1 — serialize the handle swaps

`modules/mono/csharp_script.cpp`

`refcount_incremented` and `refcount_decremented` mutated `gchandle` with **no lock at
all**, while the release path takes `CSharpLanguage::script_gchandle_release_mutex`. So a
loading thread and the finalizer thread could interleave inside the swap and both reach
`CustomGCHandle.Free` on the same handle. **That is a double free, not merely an assert.**

Both functions now take `script_gchandle_release_mutex` around the whole
save/null/swap/assign sequence, and both gained a `!gchandle.is_released()` guard so a
released handle is never handed to the swap.

The same treatment is applied to `CSharpLanguage::_instance_binding_reference_callback`,
which is the identical defect on the instance-binding path (#112067). Its decrement branch
already had the `!gchandle.is_released()` guard; its increment branch did not, which is the
direct cause of the `Handle is not initialized` exception above.

Two facts make holding this mutex across the managed call safe, and **both must stay true**:

- `Mutex` is `std::recursive_mutex` (`core/os/mutex.h:97`), so re-entering from the same
  thread — which happens via `_internal_new_managed()` → `release_script_gchandle()` — does
  not self-deadlock.
- Calling managed code while holding this mutex is already the established pattern:
  `release_script_gchandle_thread_safe()` calls `GCHandleBridge_FreeGCHandle` under it.

### Layer 2 — stop aborting on a state the code already handles

`modules/mono/csharp_script.cpp`, `mono_object_disposed_baseref`

The `CRASH_COND(gchandle.is_released())` is removed. With layer 1 in place a released
handle here has exactly one meaning: the swap found the target already collected and freed
it. Every path below the assert was already written for that case:

- `_unreference_owner_unsafe()` does not touch the handle.
- `release_script_gchandle_thread_safe()` only frees a handle that is still held **and**
  matches the one being freed, so it is a no-op and cannot double free.
- `_internal_new_managed()` builds a fresh managed side when the native object outlived its
  wrapper.

That last point matters: **this is the mechanism the .NET maintainer wanted** (see
"Alternatives" below). It already exists in the engine — the assert is simply what made it
unreachable in debug builds.

### Layer 3 — do not resurrect a dead wrapper out of the cache

`core/io/resource.cpp`, `core/object/script_instance.h`, and the C# glue.

This is the layer that fixes the **data loss**, and it is the reason the patch is worth
carrying at all. Layer 2 alone converts the abort into "resource silently comes back with
default values", which is already the release-build behavior today.

A new virtual is added to `ScriptInstance`:

```cpp
virtual bool is_script_side_alive() const { return true; }
```

Core cannot know about C#, so this is how it asks. `ResourceCache::get_ref` consults it
**before** constructing the `Ref`, and on a dead script side erases the entry and reports a
miss — the same shape as the existing mid-deletion branch right below it. The loader then
reads from disk and the resource comes back **with its authored values**.

`CSharpInstance::is_script_side_alive()` answers by:

1. returning `true` if the runtime is not up (nothing can have been collected, and we do not
   want to perturb the cache during startup or shutdown);
2. returning `false` for an already released handle;
3. returning `true` for a strong handle without any managed call, since a strong handle
   pins its target by definition;
4. otherwise calling the new `GCHandleBridge.CheckGCHandle`, which only reads
   `GCHandle.Target`. **It must never allocate, resurrect, or run user code** — see the lock
   order note below.

Glue plumbing for that callback: `GCHandleBridge.cs`, `ManagedCallbacks.cs`,
`gd_mono_cache.h`, `gd_mono_cache.cpp`.

Layers 1 and 2 remain necessary as the backstop, because the target can be collected in the
window right after the check returns.

## Invariants a future edit could break

- **Lock order is `ResourceCache::lock` → `script_gchandle_release_mutex` → managed.**
  `get_ref` holds the cache lock while `is_script_side_alive()` takes the handle mutex. If
  anything on the handle-mutex side ever starts taking `ResourceCache::lock`, that inverts
  and deadlocks. This is why `CheckGCHandle` must stay a pure target read.
- **Do not call `_internal_new_managed()` from `refcount_incremented`.** It looks like the
  obvious "just rebuild it here" fix and it is wrong: `_reference_owner_unsafe()` asserts
  `CRASH_COND(unsafe_referenced)`, and at that point the collected wrapper's reference is
  still outstanding. The recreation is only correct *after* `_unreference_owner_unsafe()`,
  which is exactly where `mono_object_disposed_baseref` already does it.
- `MonoGCHandleData::release()` nulls `handle` but **leaves `type` unchanged**, so
  `is_weak()` still reports the pre-release type on a released handle. Do not write
  conditions that rely on `is_weak()` being meaningful after release.

## Alternatives that were rejected

- **Softening the assert to `CRASH_COND(!gchandle.is_weak() && gchandle.is_released())`.**
  This is [PR #87045](https://github.com/godotengine/godot/pull/87045), which upstream
  **closed**. paulloz: *"We believe this does not fix the core issue (although it hides the
  symptoms by bypassing the crash condition)."* Correct call — on its own it leaves the
  double free and the data loss untouched. Our layer 2 removes the condition outright rather
  than narrowing it, and is only defensible because layers 1 and 3 sit underneath it.
- **Recreating the managed instance on resurrection, and nothing else** (paulloz's preferred
  long-term avenue). It covers code paths the cache fix does not, but it cannot recover the
  exported values, because those lived in the collected managed object's fields. We get this
  behavior anyway via layer 2 as the general backstop, with layer 3 ensuring the case that
  actually matters reloads real data instead.
- **`CACHE_MODE_IGNORE` / `IgnoreDeep`.** Does not help. `get_ref` runs before the cache
  mode is examined, and taking the reference is the damage; ignore only discards the result.
- **`GC.SuppressFinalize` on wrappers.** Trades the abort for a native leak and a script
  instance whose managed side never returns.
- **`GC.Collect()` + `WaitForPendingFinalizers()`.** Finalization is chained here — the
  `PackedScene` finalizer is what drops the sub-resource to one holder — so one round is not
  enough, and a collection can still land after any drain.
- **Keeping resources alive for the session** (the mitigation the game project uses). Hides
  the bug; does not fix it. This patch must not assume it is present.

## Upstream context

paulloz (.NET maintainer), 2026-08-17 on #83762, named two avenues: (1) block the cache from
resurrecting invalid objects, (2) create a new managed instance when the cache resurrects
something. He called his own prototype of (1) *"obviously just quick and dirty"* and said he
believed (2) *"might be a better solution long-term; I'm not convinced we can rule out that
other unexpected code paths can result in the same kind of issue."* He offered to discuss a
proper patch on Rocket.Chat.

This patch deliberately does both: (1) for the cache path, because it is the only way to get
authored values back, and (2) as the general backstop, which answers his concern about
unknown code paths.

Note that the widely circulated community patch
([brokolja@cbd2e14](https://github.com/brokolja/godot/commit/cbd2e14e8783baa50ebe07e399e08bc02ebe6594))
is **not** independent corroboration — it is paulloz's prototype (same
`refcount_needs_resurrect`/`refcount_can_resurrect` shape) plus the mutex plus the rejected
assert narrowing. We took the mutex idea from it and diverged on the rest. In particular we
did **not** take paulloz's `return true` in `refcount_decremented`'s `!target_alive` branch:
returning "it can die" while a finalizer is still queued for the same object risks the
finalizer touching a deleted owner. Letting the finalizer do the deletion is safer and, with
layer 2, it now runs.

If upstream lands its own fix, **drop this patch rather than merging it** — the two will not
compose, and anything upstream ships will be the one the GodotSharp packages are built
against.

## Verification

A reproduction harness lives at `/home/jason/Projects/godot/engine-tests/gchandle-race`
(not in this repo, and not a git repo itself). `./run.sh` drives the whole pipeline. See its
README for the mechanism; the short version is that the race window is only microseconds
wide, so the harness holds the finalizer thread shut with a batch of blocking finalizers
while the main thread performs the reload.

Measured 2026-09-15, 400 iterations each, debug editor builds:

| Engine | Result |
| --- | --- |
| This patch on `4.7.2-stable` (`4.7.2-slopworks`) | **PASS** — 400/400, 0 value mismatches |
| Stock `4.7.2-stable`, control | **ABORT** on iteration 0 |
| Unpatched official `4.7.1-stable-mono` | **ABORT** on iteration 0 |

Every unpatched build dies with the original crash, on the .NET finalizer thread:

```
FATAL: Condition "gchandle.is_released()" is true.
   at: mono_object_disposed_baseref (modules/mono/csharp_script.cpp:1788)
```

The second row is the control that matters: a worktree at the same `4.7.2-stable` tag built
identically, so the patch is the only variable. Without it the 4.7.1 result alone would be
confounded by the version difference.

The same three-way result was also measured on the earlier `4.7.3-rc` base before this
branch was moved to the tag, which is some evidence the fix is not sensitive to the base.

**Failure mode 2 (silent data loss) is NOT verified.** It is only observable with
`DEBUG_ENABLED` off, and there is currently no working way to run the harness on one:
`template_release --path .` segfaults at startup on patched and unpatched builds alike (so
it is an unsupported configuration, not a difference), and a real `--export-release` produces
a binary whose C# side segfaults immediately. The claims about mode 2 in this document are
reasoned from the source and from the original brief, not measured. The harness already
asserts the exported values, so it will catch it as soon as a release build can be run.

Two false negatives are worth knowing about, because both look like passes:

- `GC.Collect()` + `GC.WaitForPendingFinalizers()` then reload **cannot** reproduce this.
  Draining the queue is exactly what closes the window; the resource ends up fully disposed
  and evicted, so the reload is a clean cache miss with correct values.
- A tight load/drop loop with a background GC thread also cannot: the scene is re-referenced
  from the cache every iteration and nothing is ever released. 20000 iterations ran in under
  a second, all cache hits.

Other repro projects, not yet run here: `gchandle_repro.zip` (brokolja) and `SchoolGame.zip`
(RobProductions) on #83762, `handle-mrp.zip` (DragoonX6) on #112067.

## Distribution cost

Layer 3 changes managed glue, so this is not just an engine rebuild: the editor, the export
templates, **and** the GodotSharp NuGet packages must be rebuilt and pinned, and every
developer machine and CI runner has to use those builds.

## Conflict guidance on rebase

- `core/io/resource.cpp` — the hunk sits in `ResourceCache::get_ref`. If upstream reworks
  the cache, the requirement is unchanged: ask before constructing the `Ref`, and on a dead
  script side erase the entry and report a miss.
- `modules/mono/csharp_script.cpp` — four sites: the two `refcount_*` swaps, the disposal
  assert, and `_instance_binding_reference_callback`. If upstream adds its own locking,
  check for double-locking before keeping ours.
- If `ScriptInstance` gains an upstream virtual with the same purpose, switch to it and
  delete ours rather than carrying both.
