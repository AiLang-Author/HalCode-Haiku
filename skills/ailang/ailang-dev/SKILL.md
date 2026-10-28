---
name: ailang-dev
description: Writing, editing, and compiling AILang source. Use when working on .ailang files, compiler errors, or HalCode9000 / cc_tools. Ground truth is Ailang-Self-Hosting Librarys/Compiler, not Demo Programs.
---

# AILang Development

Ground truth: `/home/bob/Ailang-Self-Hosting-/Librarys/Compiler/` and `Librarys/Library.*.ailang`.
Do **not** copy APIs from `Demo Programs/` — those predate the Hash/Array rewrite and several lexer/ABI fixes.

## Compiler

```bash
# After sudo ./install_compiler.sh in Ailang-Self-Hosting-
ailang.x [-P] [-D1-4] [-d] source.ailang [output.x]   # default out: a.out
analyzer.x source.ailang [function_filter]            # 4 analysis passes, not a syntax-only dry run
```

HalCode rebuild is **this repo**, not the compiler tree:

```bash
cd /home/bob/HalCode9000
./build.sh              # needs ailang.x on PATH
./build.sh --no-tools
./build.sh --tools-only
```

Compiler install: `sudo /home/bob/Ailang-Self-Hosting-/install_compiler.sh`.
There is no HalCode `build.sh` under a Sean WSL path.

## Language rules (current compiler)

- **`SystemCall(nr, a1..a6)`** — max 6 args **after** the number. Extra args are a **compile error** (`CCompileSystem`). Linux syscall regs: **RDI RSI RDX R10 R8 R9** (arg4 is R10, not RCX). Function calls use RCX as arg4.
- **Function `Input:` > 6** — analyzer warning; x86 backend only spills 6 register args. Group extras in a FixedPool.
- **`SYS_*` names are yours.** The compiler takes an integer. Put numbers in a `FixedPool` (`SYS_READ=0`, `SYS_WRITE=1`, …).
- **`StoreValue(addr, val)`** = 8-byte qword. Optional 3rd arg: `"byte"|"word"|"dword"|"qword"`. Same hints on `Dereference(addr[, hint])`.
- **`SetByte(addr, offset, value)`** — **3 args**. `GetByte(addr, offset)` — **2 args**. Two-arg `SetByte(buf, 72)` does not compile.
- **`Deallocate(addr, size)`** — **2 args**. `Allocate`/`Deallocate` need `LibraryImport.Arena`. `Deallocate(p, 0)` is **Free24** (24-byte slab), not auto-size.
- **Strings:** `"hello\n"` is valid. A **raw newline inside quotes** is `Newline in string literal`. Escapes: `\n \t \r \\ \" \0`. Data is **NUL-terminated**, not length-prefixed. No `'x'` char literals — use ASCII integers (`72` for H).
- **`StringConcat(a, b)`** is a **compiler builtin**, not StringUtils.
- **`LibraryImport.Name`** required; resolved from the compiler install dir.
- **FixedPool keys are string literals:** `"field": Initialize=0, CanChange=True`.
- Control: `IfCondition expr ThenBlock: { } ElseBlock: { }`, `WhileLoop cond { }`, `BreakLoop` / `ContinueLoop`, `ReturnValue(...)`.
- Types: Integer, Address, Text, Boolean, Void, Any.

### Function form

```
Function.MyFunc {
    Input: param1: Address
    Input: param2: Integer
    Output: Address
    Body: {
        ReturnValue(result)
    }
}
```

Also: `SubRoutine.Name`, `InlineFunction.Name`, `ExternalKernelFunction.Name` (no Body). `Input: (a: T, b: T)` is allowed.

### Byte string construction

```
buf = Allocate(256)
SetByte(buf, 0, 72)     // 'H'
SetByte(buf, 1, 101)    // 'e'
SetByte(buf, 2, 0)
```

## Collections (do not use dead names)

| Dead (demos / old skills) | Live import |
|---|---|
| `HashMap`, `THash` | `LibraryImport.Hash` → `Hash.*` (string keys, CRC32) |
| `TArrays`, `XArrays` | `LibraryImport.Array` / `Arrays` → `Array.*`, `SHash.*`, `IHash.*` |
| `TimeDate.tick/now/sleep` | `LibraryImport.TimeDate` → **`Time.*`** (`Time.Unix`, `Time.Sleep` in **ms**) |

JSON objects are **SHash**, arrays are **Array**. See `ailang-lib-json`.

## Sockets

cc_tools: abstract `@halcode/Name`, `Socket.Create(1, 1)` = AF_UNIX + SOCK_STREAM, then `SendMsg`/`RecvMsg` (4-byte BE length + JSON). Not SEQPACKET. Not `/tmp/*.sock`.

## WSL2 (this machine)

Never `find /`, `/mnt`, or `/mnt/c` — hangs on NTFS. Scope find. Pipe unbounded output.
