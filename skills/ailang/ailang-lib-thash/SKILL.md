---
name: ailang-lib-thash
description: THash does not exist. THash.mix64/combine/bytes are gone. Use Library.Hash Hash.HashString/CRC32.
---

# THash does not exist

`THash.mix64`, `THash.combine`, and `THash.bytes` **do not exist**. There is no `LibraryImport.THash`.

Use `LibraryImport.Hash`:

- `Hash.HashString(str: Address) → Integer` — hardware CRC32 over bytes; never 0
- `Hash.CRC32Step(crc: Integer, byte_val: Integer) → Integer` — one-byte SSE4.2 `CRC32`

For a map: `Hash.New` / `Hash.Set` / `Hash.Get` (string keys). See `ailang-lib-hashmap`.

Copyright (c) 2026 Sean Collins, 2 Paws Machine and Engineering. Licensed under SCSL.
