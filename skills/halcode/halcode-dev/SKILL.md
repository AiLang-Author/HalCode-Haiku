---
name: halcode-dev
description: Developing and iterating on HalCode9000 itself — building the binary and cc_tools, understanding the repo layout, and navigating known architectural constraints. Load this when working on HalCode9000 source, cc_tools, or backends.
---

# HalCode9000 Development

## Repo Layout

```
/mnt/c/Users/Sean/Documents/HalCode9000/          ← Windows-side working copy
/mnt/c/Users/Sean/Documents/AILangSH/             ← compiler + stdlib root
/mnt/c/Users/Sean/Documents/AILangSH/Applications/HalCode9000/  ← build output lives here
```

The two HalCode9000 directories are **mirrors** — edits go in the Documents/HalCode9000 copy, builds run from AILangSH.

---

## Build

```bash
# From /mnt/c/Users/Sean/Documents/AILangSH/
./build.sh                 # rebuild HalCode9000 binary + all cc_tools
./build.sh --no-tools      # main binary only (fast iteration on HalCode9000.ailang)
./build.sh --tools-only    # cc_tools only

# Compile a single file
./ailang.x path/to/source.ailang path/to/output.x

# Syntax check without compiling (catches most errors faster)
./analyzer.x path/to/source.ailang
```

---

## Architecture

```
HalCode9000.ailang          entry, startup, provider menu, agent loop
backends/Anthropic.ailang   Anthropic wire format
backends/OpenAI.ailang      OpenAI + compatible clones (Groq, DeepSeek, xAI, etc.)
backends/Gemini.ailang      Google Gemini
backends/Backend.ailang     provider dispatch + Backend.Init
cc_tools/*.ailang           IPC tool daemons (each binds an abstract socket)
cc_tools.json               tool registry (binary + socket path)
providers/*.json            per-provider config (URL, auth, models, pricing)
~/.halcode/skills/*.md      skill sheets loaded at session start
```

**Internal message format**: OpenAI schema. Each backend translates to/from its own wire format on outbound.

---

## Abstract Socket Namespace

```
@halcode/*   — standard cc_tools (Read, Write, Bash, Grep, etc.)
@halcore/*   — privileged tools: Relmem, Pgmem, Agent
```

Don't mix namespaces. The split is a convention, not a security boundary, but breaking it causes confusion.

---

## Known Architectural Constraints

### Library.JSON hash-collision bug
`"name"` and `"index"` hash to the same bucket. Workarounds already in place:
- **Anthropic backend**: uses parallel `tool_names[]`/`tool_ids[]` arrays — don't try to read `"name"` from tool_use JSON
- **OpenAI backend**: `OpenAI_BuildAssistantMsgStr()` builds assistant messages as raw string via `StringConcat` + `JSON.EscapeString`, then re-parses — bypasses XSHash entirely

Any new field named `"name"` is suspect. Test carefully.

### Integer kind field for backend dispatch
`SelectedProvider.kind`: 1=Anthropic, 2=OpenAI, 3=Gemini. Never dispatch by string comparison — the arena allocator can recycle the string pointer between auth and init.

### Write tool: no custom connections
Custom connections (non-provider-json configs) are stored via raw `StringConcat`, **not** `Library.JSON`, because XSHash corrupts `key_hint` and `default_model` on write. Don't refactor this to use Library.JSON.

### No recursive sub-agents
The Agent tool spawns `HalCode9000.x --agent`. Child processes cannot call the Agent tool. Design hierarchical workflows with the parent as the only orchestrator.

### MCP uses JSONL framing
HalCode9000's MCP server uses newline-delimited JSON, not `Content-Length` framing. This is intentional — the AILang JSON parser doesn't do incremental/chunked parsing.

---

## IPC Tool Pattern

Every cc_*_ipc tool follows this structure:

```
FixedPool constants
BuildSchema()         → returns tool schema sent to model on connect
DoWork()              → main handler
SendError / SendResult / SendSchema
HandleRequest()       → dispatch loop
Main()                → bind socket, accept loop
```

When adding a new tool: copy an existing simple tool (e.g. cc_stat_ipc.ailang), update `SOCK_PATH`, `BuildSchema`, and `DoWork`. Add entry to `cc_tools.json`.

---

## AILang Sharp Edges

- **6-arg syscall limit** — SysV AMD64 uses RDI/RSI/RDX/RCX/R8/R9. analyzer.x enforces this.
- **StoreValue** defaults to 8-byte (qword). `StoreValue(addr, val, "dword")` for 4-byte.
- **No trailing literal `\n`** — never end a `.ailang` file with backslash-n text. It must be a real newline byte or the lexer will reject the file.
- **MemoryCopy/MemorySet** emit CLD + REP MOVSB/STOSB with register save/restore.

---

## cc_tools Syscall Numbers (x86-64 Linux)

| Name | Number |
|------|--------|
| SYS_READ | 0 |
| SYS_WRITE | 1 |
| SYS_OPEN | 2 |
| SYS_CLOSE | 3 |
| SYS_PIPE | 22 |
| SYS_DUP2 | 33 |
| SYS_FORK | 57 |
| SYS_EXECVE | 59 |
| SYS_WAIT4 | 61 |
| SYS_MKDIR | 83 |
| SYS_UNLINK | 87 |
