---
name: ailang-lib-json
description: Library.JSON tagged-value parser/builder. Load when parsing or building JSON in backends or cc_tools. SetString aliases; Free vs FreeObject/FreeArray; numbers are Integer not strings.
---

# Library.JSON (ailang)

Ground truth: `/home/bob/Ailang-Self-Hosting-/Librarys/Library.JSON.ailang`.
There is **no** `"name"`/`"index"` hash-drop bug in current JSON. Objects are `SHash` with chaining + `StringCompare`. Sibling-key loss in HalCode was nested `SetString` **register clobber**, not a hash collision.

```
LibraryImport.JSON
```

Requires: `LibraryImport.Arrays`, `LibraryImport.StringUtils`. **Not** HashMap or XArrays.

## Tagged vs untagged

Every **parsed** value is a 16-byte tag+payload:

| Offset | Field |
|---|---|
| 0–7 | `JType` (NULL=0 STRING=1 NUMBER=2 BOOL=3 OBJECT=4 ARRAY=5) |
| 8–15 | payload |

`JSON.NewObject` / `JSON.NewArray` return **untagged** containers (SHash / Array). Do not pass them to `JSON.Serialize` or `JSON.Free`.

| You have | Serialize with | Free with |
|---|---|---|
| tagged parse tree (`ParseJSON`) | `JSON.Serialize(v)` | `JSON.Free(v)` |
| `NewObject` SHash | `JSON.SerializeObject(obj)` | `JSON.FreeObject(obj)` |
| `NewArray` Array | `JSON.SerializeArray(arr)` | `JSON.FreeArray(arr)` |

## Ownership (HalCode actually burned here)

- **`JSON.SetString` aliases.** The value pointer is stored as-is. Only the **key** is copied inside `SHash.Insert`.
- **`JSON.Free` on STRING does `Deallocate(value, strlen+1)`.** Do not Free a tree that still holds literals or live buffers. Heap-copy (`CC_StrDup` / `Allocate`+copy) anything you store then Free.
- **`Deallocate(p, 0)` is Arena Free24**, not auto-size. Serialize output: `Deallocate(out, StringLength(out)+1)`.

## Construction

```
obj = JSON.NewObject()
JSON.SetString(obj, key, s)     // s must stay alive or be heap-owned
JSON.SetNumber(obj, key, n)     // n is Integer, not a string
JSON.SetBool(obj, key, b)
JSON.SetNull(obj, key)
JSON.SetObject(obj, key, v)
JSON.SetArray(obj, key, v)

arr = JSON.NewArray()
JSON.PushString(arr, s)         // no Output (does not return length)
JSON.PushNumber(arr, n)         // n is Integer
```

Getters: `GetString`/`GetNumber`/`GetBool`/`GetObject`/`GetArray`/`GetType`.
`GetNumber` / `AsNumber` return **Integer** (via `StringToNumber` on parse).
`ArrayGet(arr, i)` / `ArrayLength(arr)`.
Introspection: `JSON.TagType(v)`, `JSON.TagValue(v)`. `JSON.Tag(vtype, value)` is a **constructor**, not a getter.

## Parse / serialize

```
root = ParseJSON(text)          // Function.ParseJSON — sets JParse itself
                                // 0 on error; check JParse.error / error_msg
out  = JSON.SerializeObject(obj)
```

Do not pre-set `JParse.buffer` before `ParseJSON`. Parse helpers (`ParseValue`, …) take **no** text argument; they use `JParse.*`.

`JSON.EscapeString` copies with `"` `\` `\n` `\r` `\t` and `<32` as `\uXXXX`. It does **not** quote; `Serialize` adds quotes. No `/` escape, no high-byte `\u`.

`JSON.BuildObject` / `BuildArray` are serialize wrappers, not empty-container constructors.

## Example (untagged object — HalCode style)

```
obj = JSON.NewObject()
JSON.SetString(obj, "status", owned_ok)   // owned_ok is heap, not a literal if you Free
JSON.SetNumber(obj, "count", 42)
out = JSON.SerializeObject(obj)
JSON.FreeObject(obj)
Deallocate(out, Add(StringLength(out), 1))
```
