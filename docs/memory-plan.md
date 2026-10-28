# Memory: no GC, two (really three) paths

AILang is bare-metal x86. There is no tracing collector and we should not add one.
`Allocate` / `Deallocate` are slab arenas: frees go to per-size freelists **inside the
process**. RSS is a high-water mark. It only flattens if new work is served from
those freelists **and** we stop allocating objects that are never returned.

Live snapshot from the stress TUI (`./HalCode9000.x`, ~11 min):

| | |
|---|---|
| RSS | 63 MB (started ~2 MB) |
| VIRT | 151 MB |
| History | 112 messages (cap is 10) |
| Request body | 317 KB (started ~26 KB) |
| Workers | 0.2–1.4 MB, flat |

Growth is linear (~1 MB / 2 messages), not a spike. It will **not** level off
while `keep_going` keeps one tool chain alive.

Architecture.md already claims “schema caching: report once at connect, never
re-parsed.” `IPCDispatch.GetToolSchemasArray()` currently re-queries every
daemon on every `BuildRequest`. Path 1 restores that claim.

---

## Why RSS cannot fall on its own

1. **Eviction refuses to drop a still-open turn.** `History_EvictIfNeeded` walks
   from the front and treats `assistant` + every `role=tool` as the same turn.
   If that *is* the whole buffer (stress loop, no new user message), it
   `BreakLoop`s and the cap never fires.
2. **DropFront does not free.** It builds a new array and aliases surviving
   objects. Dropped JSON trees leak. Even a working cap would not return RSS.
3. **Per-request JSON is fire-and-forget.** Schema re-fetch, `ParseJSON` of
   tool responses, `NumberToString` 24-byte blocks, serialize temps that we
   still miss. Those never hit a freelist.
4. **Slabs stay mapped.** Correct `Deallocate` reuses blocks next turn; it does
   not `munmap`. Live size can stabilize; RSS stays at the peak unless we
   reset a region.

Workers are not the problem. The main process is.

---

## Path 1 — Schema cache (cheap, intended)

**Where:** `IPCDispatch.GetToolSchemasArray`

**Do:** If `IPCDState.schemas_arr` is already filled from `RegisterTool` /
a previous fetch, return it. Do not `SendMsg`/`ParseJSON` 26 schemas every
API call. Refresh only after reconnect (schema pointer already stored on the
tool table).

**Must not:** `JSON.Free` the cached array while `BuildRequest` still aliases
`input_schema` into the outbound tools list. Cache is long-lived, like the
tool table.

**Expected:** Cuts a large, *constant* per-turn alloc (tens to hundreds of KB
of schema JSON × every request). Will not stop history-driven growth.

## Path 2 — Evict completed tool turns (policy)

**Where:** `History_EvictIfNeeded` / end of `CC_RunTurn` when the model
**stops** calling tools (`keep_going` about to become 0).

**Do:** Once a turn is finished (no pending tools), allow dropping the oldest
*completed* user/assistant/tool bundle even if the live buffer is still over
cap. Hard-cap tool-result bytes is already partly there (32 KB park).

**Must not:** Drop the in-flight assistant/`tool` pair of the current turn.
`JSON.Free` dropped messages only if every string in them is an owned copy
(`SetString` aliases; we already crashed that way). First version: drop
pointers, accept the leak, still shrink the **request body**. That is the
thing that will 400 / timeout first.

**Expected:** Request body stops climbing with tool-chain length. RSS still
drifts up from (3) until path 3.

## Path 3 — Per-turn scratch arena (the “GC”)

Not a collector. A **generation**:

- Long-lived heap (today’s slabs): history we still send, tool-slot
  id/name/args buffers, TUI, IPC table, schema cache.
- Scratch / bump region: `BuildRequest` serialize, SSE `ParseJSON` trees
  (already copied into `OAIState` then `JSON.Free`’d), dispatch envelopes,
  one-shot `NumberToString` / `EscapeString` temps.

At `Backend.Reset()` / end of turn: reset the scratch bump in one shot
(pointer rewind or `Arena_FreeAll` of that region only). No graph walk.

This is the AILANG-native equivalent of GC. It requires an Arena API split
(`Allocate` vs `ScratchAlloc`, or a thread-local/generation flag). **Do not**
put history or tool-slot buffers on scratch.

**Expected:** Per-turn ephemeral JSON stops accumulating. RSS plateaus at
“live history + peak scratch high-water of one turn.”

---

## Order

1. Path 1 (schema cache) — small, matches existing design text, safe.
2. Path 2 (evict finished turns) — shrinks the request; do not Free aliased
   trees in v1.
3. Path 3 (scratch arena) — needs Arena changes in `Ailang-Self-Hosting-`
   then HalCode call sites.

Measure with `/tmp/hal_mem_instrument.log`: RSS, VIRT, `History.Count()`,
request body size. Success is body size bounded after a completed turn, and
RSS growth per turn dropping toward zero once scratch reset lands.

## Out of scope

- Tracing GC, refcounts on JSON nodes, `JSON.Free` of history until ownership
  is explicit.
- Worker-side arenas (they are already flat).
