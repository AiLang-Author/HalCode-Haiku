---
name: ailang-lib-tarrays
description: TArrays is deprecated. Use Library.Array (LibraryImport.Array). Load for Array.Create/Push/Get/Set 8-byte dynamic arrays. Not tiered, not elementSize.
---

# TArrays is deprecated

Use `Library.Array`. There is no `LibraryImport.TArrays`, no `elementSize`, no tiered pages.

Ground truth: `/home/bob/Ailang-Self-Hosting-/Librarys/Library.Array.ailang`.

```
LibraryImport.Array
```

Flat dynamic array of **8-byte Integer/Address** slots. Header 32 bytes: `[magic, capacity, size, data_ptr]`. Data is one contiguous `capacity*8` block. Grows 2× on Push/Insert overflow. Default capacity 16.

Not a byte vector. Not caller-chosen stride. Not page-chained.

## API

```
arr = Array.Create(initial_capacity)   // ≤0 → 16
Array.Destroy(arr)

Array.Get(arr, index) → Integer        // 0 on OOB / null
Array.Set(arr, index, value)           // no-op on OOB; index must be < size
Array.Push(arr, value)                 // append; grows if full
Array.Pop(arr) → Integer               // last, or 0 if empty; capacity unchanged
Array.Size(arr) → Integer
Array.Capacity(arr) → Integer
Array.Clear(arr)                       // size=0; capacity unchanged
```

`Set` only overwrites live slots (`index < size`). Use `Push` to grow.

Also present: `IsArray`, `Insert`, `Delete`, `IndexOf`, `Contains`, `Copy`, `Extend`, `Reverse`, `Sort`, `Slice`, `Swap`, `Shift`, `First`, `Last`, `IsEmpty`, `Resize`, `InsertSorted`, `BinarySearch`.

Collections (Stack, Queue, List, IHash, SHash) live in `LibraryImport.Arrays`, which imports Array.

Copyright (c) 2026 Sean Collins, 2 Paws Machine and Engineering. Licensed under SCSL.
