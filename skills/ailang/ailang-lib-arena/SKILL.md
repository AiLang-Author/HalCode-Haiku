---
name: ailang-lib-arena
description: Arena allocator. Load when using Allocate/Deallocate or scratch. 4MB mmap chunks; ScratchBegin/End rewind; Deallocate(p,0) is Free24 not a no-op.
---

# Library.Arena (ailang)

Ground truth: `/home/bob/Ailang-Self-Hosting-/Librarys/Library.Arena.ailang`.

```
LibraryImport.Arena
```

User-facing primitives (compiler → `Arena_Alloc` / `Arena_Free`):

```
ptr = Allocate(size)
Deallocate(ptr, size)     // size MUST match the allocation
```

## Layout (current)

`ArenaConst.CHUNK_SIZE` is **4194304 (4MB)**, not 64KB.

Slabs: 24, 32, 64, 128, 256, 512, 1024, 2048, 4096, **8192, 16384, 32768, 65536**.
Allocations **> 65536** go to `Arena_LargeCacheAlloc` (mmap, **can** be cached on free). `ArenaGeneral` is effectively unused.

Chunk: `[0-7]=next`, bump from `+8`.

## Scratch (what HalCode uses around BuildRequest/stream)

```
Arena_ScratchBegin()    // on=1; rewind to scratch head
// Allocate here — bump 4MB chunks; Arena_Free is a no-op while scratch is on
Arena_ScratchEnd()      // on=0; rewind to first chunk; pages stay mapped
```

This is the real “free is a no-op” mode — **not** `Deallocate(p, 0)`.

## Footguns

- **`Deallocate(ptr, 0)` / `size=0` → `Arena_Free24`**, not a no-op. Corrupts the 24-byte slab if `ptr` was not a 24-byte slot. JSON comments say the same.
- Wrong `size` on Free routes to the wrong slab.
- `Arena_Reset` / `Arena_FreeAll` only cover **24–4096 + general**. They do **not** rewind 8K–64K slabs, scratch, or the large-mmap cache.

## Other

`Arena_Init` at startup. `Arena_MmapDirect(size)` page-aligned mmap (regex DFA buffers). `Arena_ArrayCreate` / `Arena_ArrayResize` / `Arena_ArrayDestroy` / `Arena_Report` exist; normal code uses `Allocate`/`Deallocate`.
