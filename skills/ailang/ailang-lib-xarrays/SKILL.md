---
name: ailang-lib-xarrays
description: XArrays does not exist. Use Library.Array and Library.Arrays. JSON uses Arrays, not XArrays.
---

# XArrays does not exist

There is no `LibraryImport.XArrays`, no `XArrays_Int` / `XArrays_Ptr`, no typed-array macros.

- Arrays: `LibraryImport.Array` — `Array.Create` / `Get` / `Set` / `Push` / `Pop` / `Size` / `Destroy`
- Collections: `LibraryImport.Arrays` — Stack, Queue, List, IHash, **SHash**
- JSON uses `LibraryImport.Arrays` (`SHash` objects, `Array` arrays), not XArrays

See `ailang-lib-tarrays`.

Copyright (c) 2026 Sean Collins, 2 Paws Machine and Engineering. Licensed under SCSL.
