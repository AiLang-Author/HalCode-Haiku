---
name: ailang-lib-hashmap
description: HashMap is deprecated. Use Library.Hash (LibraryImport.Hash). Load for Hash.New/Create/Set/Get string-keyed maps. IHash/SHash live in Arrays.
---

# HashMap is deprecated

Use `Library.Hash`. There is no `LibraryImport.HashMap`.

Ground truth: `/home/bob/Ailang-Self-Hosting-/Librarys/Library.Hash.ailang`.

```
LibraryImport.Hash
```

Requires `LibraryImport.Array` (Keys/Values return Array). Hash itself already imports Array.

Open-addressing string hash table, hardware CRC32, linear probing, tombstones, auto-resize at 70% load. Capacity is power-of-two, min 8.

| | |
|---|---|
| Keys | Address (C strings). Table owns a copy. |
| Values | Integer (ints, bools, or pointers) |
| Missing Get | `0` — use `Contains` if `0` is a valid value |

## API

```
h = Hash.New()                    // Hash.Create(16)
h = Hash.Create(capacity)         // rounded up to 2^n, min 8

Hash.Set(h, key, value) → 1|0     // 1 = new key, 0 = update
Hash.Get(h, key) → Integer        // 0 if missing
Hash.Contains(h, key) → 1|0
Hash.Delete(h, key) → 1|0         // tombstone; does not shrink
Hash.Size(h) → Integer
Hash.Clear(h)                     // frees keys, keeps capacity
Hash.Destroy(h)                   // frees keys + table

ks = Hash.Keys(h)                 // Array of live key pointers — do not free strings
vs = Hash.Values(h)               // Array of Integer values
```

`Keys`/`Values` are fresh Arrays; caller `Array.Destroy` them. Key pointers stay valid only while that key remains in the table.

Also present (not required for basic use): `Hash.HashString`, `Hash.IsHash`, `Hash.Items`, `IncrBy`, `MSet`/`MGet`, nested `HSet`/`HGet`/…/`DestroyNested`.

## Other hash tables (LibraryImport.Arrays)

| | Keys | Notes |
|---|---|---|
| `IHash` | Integer | chained; `Create`/`Insert`/`Lookup`/`Destroy`. Lookup miss = `XERROR` |
| `SHash` | string | chained; used by JSON. `Create`/`Insert`/`Lookup`/`Exists`/`Delete`/`Keys`/`Destroy`. Addr variants store pointers |

Prefer `Hash.*` for new string maps. JSON still uses `SHash`.

Copyright (c) 2026 Sean Collins, 2 Paws Machine and Engineering. Licensed under SCSL.
