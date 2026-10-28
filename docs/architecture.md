# HalCode9000 — Architecture Document

> **For engineer onboarding.** Covers every subsystem: entry points, backends, tools,
> IPC protocol, history, UI, provider config, MCP server mode, sub-agents, and
> WSL2-specific concerns. Pgmem and Relmem are external plugins and are not
> documented here.

---

## 1. Overview

HalCode9000 is a **native AILang terminal coding agent** — zero Node, zero Python,
zero Bun. It speaks to multiple LLM backends (Anthropic, OpenAI, DeepSeek, Grok,
Gemini, Groq, Ollama), dispatches tool calls to 15 persistent IPC worker processes,
and can call external memory plugins. The whole system — main binary +
all 15 workers — compiles to ~2.2 MB of statically-linked x86-64 Linux ELF.

```
  You  →  HalCode9000.x  →  Provider API  →  SSE stream  →  Tools  →  IPC workers
```

**Three runtime modes:**
| Mode | Flag | Use case |
|------|------|----------|
| TUI (interactive) | *(default)* | Full-screen terminal chat with animated prompt |
| Headless agent | `--agent <provider>` | Spawned by the `Agent` tool for parallel sub-tasks |
| MCP server | `--mcp` | Exposes all 15 tools to Claude Code via JSON-RPC/stdio |

---

## 2. High-Level Architecture

```
                          HalCode9000.x (2542 LOC)
 ┌──────────────────────────────────────────────────────────────┐
 │  Main()                                                      │
 │    ├─ CC_ChdirToBinDir()       // CWD = binary directory      │
 │    ├─ CC_KillStaleTools()      // pkill -f cc_.*_ipc          │
 │    ├─ CC_BootTools()           // fork+exec all 15 workers    │
 │    ├─ CC_RunAuth()             // provider menu → OAuth/API   │
 │    ├─ Backend.Init()           // route to correct backend    │
 │    ├─ UI.Init()                // raw-mode TUI grab           │
 │    ├─ CC_ChatLoop()            // input → turn → repeat       │
 │    └─ Shutdown                 // kill children, restore term  │
 └──────────────────────────────────────────────────────────────┘
        │                     │                     │
        ▼                     ▼                     ▼
 ┌──────────────┐  ┌────────────────────┐  ┌─────────────────┐
 │  backends/   │  │  IPCDispatch.ailang│  │  UI.ailang       │
 │              │  │  (476 LOC)          │  │  (2110 LOC)      │
 │ Backend.ail  │  │                    │  │                  │
 │  (395 LOC)   │  │  15 persistent     │  │  Raw-mode TUI    │
 │              │  │  connections to    │  │  Bottom-pinned   │
 │ Anthropic    │  │  cc_*_ipc.x via    │  │  prompt, mascot  │
 │  (613 LOC)   │  │  abstract Unix     │  │  animations,     │
 │ OpenAI       │  │  sockets           │  │  state colors    │
 │  (622 LOC)   │  │  (@halcode/Name)   │  │                  │
 │ Gemini       │  │                    │  │                  │
 │  (564 LOC)   │  │  4-byte BE length  │  │                  │
 │              │  │  + JSON body       │  │                  │
 └──────────────┘  └────────────────────┘  └─────────────────┘
        │                     │
        ▼                     ▼
 ┌──────────────────────────────────────────────────────────────┐
 │                  15 × cc_*_ipc.x (5692 LOC total)            │
 │  Read  Head  LS  Write  Edit  Bash  Find  Grep  Git          │
 │  WebFetch  JS  MCP  Agent  Pgmem  Relmem                     │
 └──────────────────────────────────────────────────────────────┘
        │                     │
        ▼                     ▼
 ┌──────────────┐  ┌──────────────────────┐
 │  external    │  │  external            │
 │  plugins     │  │  plugins             │
 └──────────────┘  └──────────────────────┘
```

---

## 3. Entry Points

### 3.1 `HalCode9000.x` (TUI mode — default)

1. **Startup animation** (`UI.StartupAnimation()`) — optional Kitty Graphics Protocol splash
2. **Auth** (`CC_RunAuth()`) — cooked-mode provider selection menu → API key / OAuth flow
3. **Tool boot** (`CC_BootTools()`) — `fork+exec` all 15 `cc_*_ipc.x` workers; each binds an abstract Unix socket
4. **Tool registration** (`IPCDispatch.RegisterTool()`) — connects to each socket, fetches its JSON schema, caches it
5. **Raw-mode TUI** (`UI.Init()`) — alt-screen, non-canonical input, bracketed paste
6. **Chat loop** (`CC_ChatLoop()`) — reads input via `UI.ReadLine()`, runs `CC_RunTurn()`
7. `/quit` → `UI.Shutdown()`, `CC_KillAllChildren()`, exit

### 3.2 `HalCode9000.x --agent <provider>[:model]` (headless mode)

Used by the `Agent` tool to spawn sub-agents. The parent forks `HalCode9000.x --agent deepseek`, pipes the task prompt to stdin, and reads the assistant response from stdout.

1. No splash, no auth menu — skips straight to `CC_SetupAgentProvider(spec)`
2. Reads **entire stdin** into `prompt_buf` (1 MB)
3. Injects the **WSL2 RULES** system prompt (12 rules for safe WSL2 operation)
4. Calls `CC_RegisterToolsOnly()` — connects to parent's already-running `@halcode/*` sockets
5. `History.AppendUser(prompt)`, runs one `CC_RunTurn()`
6. Extracts the last assistant message from history and writes it to stdout

### 3.3 `HalCode9000.x --mcp` (MCP server mode)

Exposes all 15 tools as an MCP (Model Context Protocol) JSON-RPC server over stdio.

1. Responds to `initialize` **immediately** (~120 ms) so Claude Code health checks pass
2. Redirects stdout to stderr during boot (keeps the MCP stream clean)
3. Boots all 15 tools in the background (~12 s)
4. Speaks **JSONL** (newline-delimited JSON, not `Content-Length` framing)
5. Handles: `initialize`, `notifications/initialized`, `ping`, `tools/list`, `tools/call`
6. For `tools/call`, routes through `IPCDispatch.Dispatch()` exactly like TUI mode

```
Claude Code  ──JSONL/stdio──▶  HalCode9000.x --mcp
                                  │
                                  ├─ initialize        → {"protocolVersion":"2025-11-25",...}
                                  ├─ tools/list        → [All 15 tool schemas]
                                  └─ tools/call        → IPCDispatch.Dispatch() → result
```

---

## 4. Backend Dispatch System

`backends/Backend.ailang` (395 LOC) is a **provider-agnostic dispatch wrapper**.
Every function in `HalCode9000.ailang` calls `Backend.*` — never `Anthropic.*` or `OpenAI.*` directly.

### 4.1 Provider routing

```ailang
Backend.Init(auth_mode, credential, system_prompt)
  → reads SelectedProvider.kind (integer: 1=ANTHROPIC, 2=OPENAI, 3=GEMINI)
  → routes to Anthropic.Init / OpenAI.Init / Gemini.Init
```

**Why integer dispatch?** A `StringCompare` on the `"backend"` string was unreliable because arena allocations in the Auth flow clobbered the string pointer between `CC_MakeProvider()` and `Backend.Init()`. The `SelectedProvider.kind` integer survives arena churn.

### 4.2 Three backends

| Backend | File | LOC | Wire format | SSE format |
|---------|------|-----|-------------|------------|
| **Anthropic** | `Anthropic.ailang` | 613 | Messages API (`/v1/messages`) | `event:`/`data:` lines |
| **OpenAI** | `OpenAI.ailang` | 622 | Chat Completions (`/v1/chat/completions`) | `data:` lines, `[DONE]` sentinel |
| **Gemini** | `Gemini.ailang` | 564 | OpenAI-compatible (`/v1beta/openai/chat/completions`) | Same as OpenAI |

OpenAI backend covers **6 providers**: OpenAI, DeepSeek, Grok (xAI), Google Gemini (compat), Groq, and Ollama (local). All speak the same Chat Completions wire format.

### 4.3 Anthropic-specific features

- **Prompt caching**: `cache_control: {type: "ephemeral"}` on system prompt + last tool definition — subsequent turns pay ~10% token cost
- **OAuth support**: `Authorization: Bearer` header path alongside `x-api-key`
- **Tool name/id workaround**: Maintains parallel `AnthState.tool_names[]` / `AnthState.tool_ids[]` arrays to bypass a `Library.JSON` XSHash collision bug where reading `"name"` from a populated `tool_use` object returns `"index"`

### 4.4 OpenAI-specific features

- **Reasoning content**: Accumulates `reasoning_content` deltas (DeepSeek chain-of-thought) into a separate buffer, displayed in dim italic — **not** mixed with the main answer text
- **Tool call delta aggregation**: OpenAI streams tool calls as deltas (index + partial function name/arguments); `OpenAI_ParseToolCallDelta()` assembles them incrementally
- **Manual JSON construction**: `OpenAI_BuildAssistantMsgStr()` builds the assistant history message as a raw JSON string to sidestep the same `Library.JSON` hash collision that would drop `tool_calls` when `reasoning_content` is present

### 4.5 Provider loader

`Backend.LoadProviders(dir)` uses raw system calls (`SYS_GETDENTS`, `SYS_OPEN`, `SYS_READ`) to list and parse JSON files from `providers/*.json` and `~/.halcode/connections/*.json`. Returns an `XArray` of parsed JSON objects. No regex, no glob — direct kernel syscall.


---

## 5. The 15 TUI Tools

Each tool is a **persistent IPC worker** (`cc_*_ipc.x`), forked once at startup and
reached via an abstract Unix socket (`@halcode/Name`). Type: `SOCK_SEQPACKET`,
4-byte big-endian length prefix + UTF-8 JSON body.

| # | Tool | Worker binary | Size | Description |
|---|------|--------------|------|-------------|
| 1 | **Read** | `cc_read_ipc.x` | 21K | Read bytes from disk at offset |
| 2 | **Head** | `cc_head_ipc.x` | 21K | Read first N lines |
| 3 | **LS** | `cc_ls_ipc.x` | 21K | List directory contents |
| 4 | **Write** | `cc_write_ipc.x` | 21K | Overwrite or append string content |
| 5 | **Edit** | `cc_edit_ipc.x` | 43K | Exact string find-and-replace |
| 6 | **Bash** | `cc_bash_ipc.x` | 22K | Shell via `/bin/sh -c` |
| 7 | **Find** | `cc_find_ipc.x` | 22K | `find` on the filesystem |
| 8 | **Grep** | `cc_grep_ipc.x` | 25K | BM/NFA/DFA text search |
| 9 | **Git** | `cc_git_ipc.x` | 22K | Git subcommand passthrough |
| 10 | **WebFetch** | `cc_webfetch_ipc.x` | 27K | HTTPS fetch (MbedTLS) |
| 11 | **JS** | `cc_js_ipc.x` | 74K | QuickJS engine execution |
| 12 | **MCP** | `cc_mcp_ipc.x` | 31K | Model Context Protocol bridge |
| 13 | **Agent** | `cc_agent_ipc.x` | 146K | Spawns `HalCode9000.x --agent` |
| 14 | **Pgmem** | `cc_pgmem_ipc.x` | 28K | External plugin. Not documented in this repo. |
| 15 | **Relmem** | `cc_relmem_ipc.x` | 78K | External plugin. Not documented in this repo. |

### 5.1 Tool registration at boot

`IPCDispatch.RegisterTool("Read")`:
1. Creates a `SOCK_SEQPACKET` socket
2. Connects to `@halcode/Read`
3. Sends `{"type":"schema"}` request
4. Reads back a JSON tool schema (name, parameters, description)
5. Caches the schema in `IPCDispatch.tool_cache`

**Schema-on-connect**: Tools report their own JSON schema when asked, so new tools
can be added without changing `IPCDispatch.ailang` at all. The dispatch layer is
fully generic.

### 5.2 Dispatch protocol

`IPCDispatch.Dispatch(tool_name, params, request_id)`:
1. Looks up the socket FD in `IPCDispatch.tool_cache[tool_name]`
2. Serializes a JSON dispatch object:
   ```json
   {"type":"dispatch","request_id":"...","params":{...}}
   ```
3. Writes 4-byte BE length + JSON
4. Reads back 4-byte BE length + response JSON on the same socket
5. Returns the parsed JSON result

### 5.3 WSL2-specific concerns

The main binary runs as an x86-64 Linux binary under WSL2. File paths must stay
within the WSL2 VHDX filesystem. All 15 workers share this constraint.
Temporary files go to well-known locations (`~/.halcode/`, the model directory,
or `/tmp`).

---

## 6. External memory plugins

Pgmem and Relmem ship as binaries in this repo. Their source, schema, and
usage are not part of this tree. Do not add that material here.

## 8. The 12 WSL2 Rules

Hard-coded in `HalCode9000.ailang` (lines 47–71) and injected into every:
- TUI system prompt: prepended to all provider requests
- Agent sub-process: prepended before the task prompt in headless mode
- MCP session: included in the `instructions` field of the `initialize` response

### 8.1 Complete rules

1. **NEVER use find with / or /mnt or Windows paths.**
2. **Locate files with the external code-index plugin. Its usage is not documented here.**
3. **Scope find to specific subdirectories.**
4. **Pipe unbounded output through head/grep/tail.**
5. **Do not ask the code-index plugin for a broad reindex.**
6. **Read parked memory through the external memory plugin. Its usage is not documented here.**
7. **Max 30 tool chains in a row, then ask user.**
8. **NO SUDO.**
9. **AILang: run `./ailang.x src.ailang dest.x` and `./analyzer.x src.ailang` via Bash to check syntax.**
10. **VCS: use Olympus tool (init, add, commit, etc).**
11. **Write tool: use absolute paths. If grandparent missing, use Bash mkdir -p. For files >200 lines, use Bash `cat << 'EOF' > file`.**
12. **Write tool blocks /etc, /proc, /sys, /dev, /bin, /usr.**

### 8.2 Rationale per rule

| Rule | Risk prevented |
|------|---------------|
| 1 | WSL2 `/mnt/c` traversal causes 10–50× slowdown, hung ops, Timeout failures |
| 2 | Forces semantic lookup — avoids scanning the entire filesystem |
| 3 | Prevents recursive `find` from hitting `/mnt` or `/proc` drift |
| 4 | Prevents token overflow from 10,000+ line `find` or `grep` results |
| 5 | Broad re-index on WSL2 VHDX causes multi-minute stalls |
| 6 | Memory-plugin usage is not documented in this repo |
| 7 | Prevents runaway tool loops exhausting the context window |
| 8 | WSL2 sudo can deadlock on `/etc/sudoers` or Windows interop |
| 9 | Explicitly confirms AILang source compiles before execution |
| 10 | Olympus VCS is the required version control for `*.ailang` files |
| 11 | `Write` only auto-creates the immediate parent; `mkdir -p` handles deeper paths safely |
| 12 | Prevents catastrophic writes to system-critical paths |


---

## 9. Conversation History

### 9.1 Structure

```
CC_History (in HalCode9000.ailang)
  │
  ├─ messages: XArray of Struct
  │     role:    "user" | "assistant" | "system"
  │     content: string (text or JSON tool blocks)
  │
  ├─ Count():    returns length
  ├─ Get(i):     returns message by index
  ├─ AppendSystem(text)
  ├─ AppendUser(text)
  ├─ AppendAssistant(tool_calls_text, answer_text)
  └─ Clear()
```

### 9.2 Storage format

Messages are stored as `Struct` objects (AILang's product type). Each message has
exactly two fields: `role` (string) and `content` (string). Tool calls from the
assistant are stored as JSON strings, collapsed into the content field alongside
the answer text.

### 9.3 Provider serialization

Each backend converts `CC_History` to its wire format:

- **Anthropic**: `Anthropic.BuildMessages(history)` constructs the `messages[]` array, excluding the system message (handled separately as `system` field)
- **OpenAI**: `OpenAI.BuildMessages(history)` constructs the `messages[]` array; system message included as `{"role":"system","content":"..."}`
- **Gemini**: Same as OpenAI via `OpenAI.BuildMessages(history)`

### 9.4 History window management

When the history approaches the provider's context limit, the system:
1. Truncates old messages (keeps system prompt + last N turns)
2. Parks truncated content with the memory plugin for potential later retrieval
3. Nothing in the current codebase implements automatic summarization (planned)

---

## 10. UI System

**File**: `src/UI.ailang` (2110 LOC) — the largest single file in the codebase.

### 10.1 Architecture

```
UI.Init()
  ├─ GrabTerminal()           // enters raw mode, alt-screen buffer
  ├─ SpawnInputThread()       // dedicated pthread for non-blocking input
  ├─ SpawnRenderThread()      // dedicated pthread for animated rendering
  └─ SpawnStatusBarThread()   // connection state updates

UI.ReadLine(prompt)
  ├─ Reads from input_thread's ring buffer (lock-free)
  ├─ Handles: backspace, delete, arrows, home/end, kill-to-end
  ├─ Handles: bracketed paste (multi-line safe)
  ├─ Handles: tab completion
  └─ Returns: line (no newline) or empty string on ^D

UI.Render(answer_text)
  ├─ Scrolling viewport with line-wrapping
  ├─ Dim italic rendering for reasoning content
  ├─ State-based colorization (thinking=cyan, writing=white, tool=magenta)
  └─ Mascot animations (6 sprites: idle, read, think, write, tool)
```

### 10.2 Mascot system

Six ASCII art sprites animate in the top-right corner based on current state:

| State | Sprite | Trigger |
|-------|--------|---------|
| `IDLE` | Hal logo, pulsing | Waiting for user input |
| `READ` | Eye icon + scanning line | Read/Head/LS in progress |
| `THINK` | Brain + rotating dots | LLM call in progress |
| `WRITE` | Pen + paper | Write/Edit in progress |
| `CODE` | `< / >` brackets | JS/Bash execution |
| `TOOL` | Wrench + gear | Any other tool call |

### 10.3 Rendering thread

The render thread runs at ~30 FPS (33 ms frame budget):
1. Reads current state from shared state machine (atomic)
2. Draws the viewport (scrolling content area)
3. Draws the bottom-pinned prompt line
4. Draws the mascot sprite (top-right)
5. Draws the status bar (connection state, model name, token count)

### 10.4 State colors

| State | Prompt color | Meaning |
|-------|-------------|---------|
| `READY` | Green `▶` | Accepting user input |
| `THINKING` | Cyan `…` | LLM is generating |
| `WAITING` | Yellow `⏳` | Tool call in flight |
| `ERROR` | Red `✗` | Last operation failed |
| `DONE` | Green `✓` (briefly) | Answer complete |

### 10.5 Accessibility

- **256-color palette** only — no truecolor, safe on any terminal
- **No Ncurses** — pure VT100/ANSI escape sequences
- **Screen reader compatible**: all semantic content appears after `\r` line-clears
- **Kitty Graphics Protocol**: optional splash screen (detected via `$TERM`)


---

## 11. Provider Configuration System

### 11.1 Provider JSON files

Stored in `providers/*.json` in the binary directory. Each file contains:

```json
{
  "name": "DeepSeek",
  "kind": "openai",
  "base_url": "https://api.deepseek.com",
  "endpoint_path": "/v1/chat/completions",
  "models": ["deepseek-chat", "deepseek-reasoner"],
  "api_key_env": "DEEPSEEK_API_KEY",
  "auth_method": "api_key",
  "default_model": "deepseek-chat",
  "max_tokens_default": 8192,
  "streaming": true
}
```

### 11.2 Connection JSON files

User overrides stored in `~/.halcode/connections/*.json`. Take precedence over
provider defaults. Allow custom base_url, model selection, and auth credentials.

### 11.3 Auth methods

| Method | Description | Used by |
|--------|-------------|---------|
| `api_key` | API key in config file or `$ENV_VAR` | OpenAI, DeepSeek, Grok, Groq, Ollama |
| `oauth` | OAuth 2.0 device flow (CLI auth) | Anthropic (optional), Gemini |
| `none` | No authentication | Ollama (local) |

### 11.4 Auth flow (cooked mode)

```
1. List providers                           // Backend.LoadProviders(dir)
2. User selects provider (number in menu)   // CC_GetChoice()
3. Detect auth method                       // provider.auth_method
4a. API key: read from env var or prompt    // CC_GetAPIKey()
4b. OAuth: device flow                      // device/authorize → user → poll token
5. Test connection                          // Backend.Ping()
6. Write ~/.halcode/connections/name.json   // persist for future
7. Return SelectedProvider struct            // kind, base_url, headers, model
```

---

## 12. The Chat Loop (One Turn)

### 12.1 `CC_RunTurn()` — the core loop

```
CC_RunTurn()
  │
  ├─ 1. Backend.Send(History)
  │      Serialize history → provider format → HTTP POST
  │      Stream SSE response
  │
  ├─ 2. SSE parse loop
  │      ├─ text delta       → UI.Render() + History.AppendAssistant()
  │      ├─ reasoning delta  → UI.Render(reasoning_buf)
  │      ├─ tool_use start   → buffer tool call
  │      ├─ tool_use delta   → accumulate args
  │      └─ message stop     → finalize
  │
  ├─ 3. If tool calls present:
  │      for each tool_call:
  │        UI.SetState(WAITING)
  │        result = IPCDispatch.Dispatch(name, params)
  │        History.AppendToolResult(name, result)
  │        UI.SetState(THINKING)
  │      goto step 1 (send tool results back)
  │
  └─ 4. Done — return to CC_ChatLoop()
```

### 12.2 Tool result injection

After all tool calls in a turn execute:
1. Each tool result is appended as a `tool_result` message to History
2. `Backend.Send()` is called again — the provider receives tool results and continues
3. Loop continues until the provider sends a `message_stop` (no more tool calls)

### 12.3 Maximum tool chains

The WSL2 rules impose a **30-chain limit** before the agent must ask the user.
Additionally, the provider may impose its own tool call limit (Anthropic: 128
tool_use blocks per turn; OpenAI: configurable).

---

## 13. Sub-Agent Architecture (`Agent` Tool)

### 13.1 Spawning

The `cc_agent_ipc.x` worker (146 KB) receives a dispatch:

```json
{
  "type": "dispatch",
  "request_id": "abc123",
  "params": {
    "subagent_type": "halcode",
    "provider": "deepseek",
    "model": "deepseek-chat",
    "task": "Analyze the following code...",
    "context_key": "long_tool_results_1",
    "result_key": "sub_agent_output_1"
  }
}
```

### 13.2 Process tree

```
HalCode9000.x (main agent)
  └─ cc_agent_ipc.x (Agent tool worker)
       └─ HalCode9000.x --agent deepseek:deepseek-chat (headless child)
            ├─ Connects to @halcode/* sockets (parent's tools)
            ├─ Runs one CC_RunTurn()
            ├─ Parks the result with the memory plugin
            └─ Exits
```

### 13.3 Communication

1. **Input**: Task prompt written to the child's stdin, or the child reads parked context
2. **Output**: Child writes last assistant message to stdout; worker captures it
3. **Side effects**: Child can call all 15 tools (shares parent's IPC sockets)
4. **Result storage**: Worker parks output with the memory plugin

### 13.4 Safety

- Child process has a **60-second timeout** enforced by the worker
- Child inherits WSL2 RULES from parent
- Child does NOT have access to `Agent` tool itself (no recursive sub-agents)
- Child stdout is captured and logged; stderr goes to `/dev/null`


---

## 14. MCP Server Mode (Detailed)

### 14.1 Boot sequence

```
HalCode9000.x --mcp
  │
  ├─ 1. Redirect stdout → stderr (keep MCP stream pristine)
  ├─ 2. Print splash to stderr
  ├─ 3. Fork child: CC_BootTools() (all 15 workers, ~12s)
  ├─ 4. Main process: JSONL read loop on stdin
  │
  ├─ 5. On "initialize":
  │     Respond immediately (~120ms with cached schema)
  │     Return: {protocolVersion, capabilities: {tools: {}}, serverInfo, instructions}
  │
  ├─ 6. On "notifications/initialized":
  │     Wait for child tools to finish booting
  │     Flush buffered tool calls
  │
  └─ 7. On "tools/call":
        IPCDispatch.Dispatch() → result → JSONL response
```

### 14.2 JSONL framing

Unlike most MCP servers that use `Content-Length` framing, HalCode9000 uses
**newline-delimited JSON (JSONL)**. Each message is exactly one line:

```
{"jsonrpc":"2.0","id":1,"result":{...}}\n
```

This was chosen because:
- The AILang JSON parser does not support incremental parsing with Content-Length
- JSONL is simpler to implement (one `readline`, one `JSON.Parse`, one `JSON.Stringify`)
- Claude Code accepts both framing methods

### 14.3 Tool schema passthrough

When `tools/list` is called:
1. The MCP handler iterates over all 15 registered tools
2. Each tool's schema (cached from boot-time schema request) is wrapped in MCP format
3. Full schemas are returned — parameter types, descriptions, and constraints

### 14.4 Child process integration

A `pipe()` connects the parent MCP process to the boot child:
- Child writes `DONE\n` when all 15 tools are ready
- Parent blocks buffered `tools/call` requests until child signals readiness
- If child dies before signaling, parent returns error for buffered requests

---

## 15. Build System

### 15.1 Compilation

All source is in AILang (`.ailang` files). The toolchain:

```
ailang.x src/HalCode9000.ailang HalCode9000.x
```

- `ailang.x` — the AILang compiler. Produces static x86-64 ELF binaries.
- `analyzer.x` — the static analyzer. Checks types, memory safety, termination.
- Both are native binaries, not scripts.

### 15.2 Source tree

```
HalCode9000/
├── HalCode9000.x          # compiled binary (built from src/HalCode9000.ailang)
├── src/
│   ├── HalCode9000.ailang  # Main entry (2542 LOC)
│   ├── IPCDispatch.ailang  # Tool IPC layer (476 LOC)
│   ├── UI.ailang           # TUI (2110 LOC) — largest file
│   └── backends/
│       ├── Backend.ailang  # Provider-agnostic dispatch (395 LOC)
│       ├── Anthropic.ailang # Anthropic Messages API (613 LOC)
│       ├── OpenAI.ailang   # OpenAI/Chat Completions (622 LOC)
│       └── Gemini.ailang   # Google Gemini via OpenAI compat (564 LOC)
├── cc_*_ipc.x              # 15 pre-compiled IPC workers
├── providers/              # Provider JSON configs
│   ├── anthropic.json
│   ├── openai.json
│   ├── deepseek.json
│   ├── gemini.json
│   ├── grok.json
│   ├── groq.json
│   └── ollama.json
├── docs/
│   ├── README.md           # User-facing documentation
│   ├── CONTRIBUTING.md     # Contributor guide
│   └── architecture.md     # This document
├── ailang.x                # AILang compiler binary
├── analyzer.x              # AILang static analyzer binary
└── example/                # Example agent scripts
```

### 15.3 Binary sizes

| File | Size | LOC equivalent |
|------|------|---------------|
| `HalCode9000.x` | ~2.2 MB | 2542 |
| `cc_agent_ipc.x` | 146 KB | — |
| `cc_js_ipc.x` | 74 KB | — |
| `cc_relmem_ipc.x` | 78 KB | — |
| `cc_edit_ipc.x` | 43 KB | — |
| `cc_mcp_ipc.x` | 31 KB | — |
| `cc_pgmem_ipc.x` | 28 KB | — |
| `cc_webfetch_ipc.x` | 27 KB | — |
| `cc_grep_ipc.x` | 25 KB | — |
| `cc_bash_ipc.x` | 22 KB | — |
| `cc_git_ipc.x` | 22 KB | — |
| `cc_find_ipc.x` | 22 KB | — |
| `cc_head_ipc.x` | 21 KB | — |
| `cc_ls_ipc.x` | 21 KB | — |
| `cc_read_ipc.x` | 21 KB | — |
| `cc_write_ipc.x` | 21 KB | — |

---

## 16. Key Design Decisions

### 16.1 AILang, not Python/Node

- **Zero runtime dependencies**: Statically compiled, no interpreter, no package manager
- **Single binary distribution**: Everything compiles to one ~2.2 MB ELF
- **Deterministic memory**: No GC pauses, arena-based allocation, stack-allocated structures
- **Direct syscall interface**: `Library.*` wraps Linux syscalls (getdents, epoll, sendmsg, etc.)

### 16.2 Persistent workers, not subprocess-per-call

- **Low latency**: Socket already connected; dispatch is ~200 µs + tool execution
- **Schema caching**: Tools report schema once at connect, never re-parsed
- **Stateful tools**: some workers keep their own connection open across calls
- **Crash resilience**: Worker crashes don't take down the main binary; auto-reconnect

### 16.3 Abstract Unix sockets (@halcode/Name)

- **No filesystem pollution**: Abstract namespace, no `/tmp` cleanup needed
- **No permissions**: Abstract sockets have no file permissions model
- **WSL2-safe**: No `/mnt/c` involvement, stays in Linux VHDX
- **Namespace isolation**: `@halcore/Pgmem` vs `@halcode/Read` prevents collisions

### 16.4 SEQPACKET framing

- **Message boundaries preserved**: No need for delimiter-based parsing in a stream
- **4-byte BE length prefix**: Simple, standard, handles payloads up to 4 GB
- **Atomic reads**: Each `recv()` returns exactly one complete message

### 16.5 Raw VT100 TUI, not Ncurses

- **Zero external dependencies**: Pure escape sequences
- **256-color**: Works on every terminal since ~2005
- **Alt-screen**: `\x1b[?1049h` — clean restore on exit (even on crash)
- **Bracketed paste**: Prevents multi-line paste injection

---

## 17. Future Architecture (Planned / Not Yet Built)

### 17.1 Persistent session resume

PG-backed session storage that survives process restart. Would restore full
conversation history, tool cache, and auth state.

### 17.2 Multi-turn sub-agents

Currently the `Agent` tool spawns one-turn headless children. Planned: persistent
sub-agents with their own history, running in the background as daemon processes.

### 17.3 Streaming tool results

Some tools (Bash, JS) produce output progressively. Currently all results are
collected and returned atomically. Planned: progressive streaming of tool output
to the provider as `tool_result` chunks.

### 17.4 Parallel tool dispatch

When multiple independent tool calls arrive in one turn, they could execute in
parallel across the 15 workers. Currently they execute sequentially.

### 17.5 Auto-compaction

When conversation history exceeds context limits, auto-summarize older turns
via a lightweight LLM call — parked with the memory plugin, replaced in the active window.

---

## 18. Appendix: Quick Reference

### Environment variables

| Variable | Purpose |
|----------|---------|
| `DEEPSEEK_API_KEY` | DeepSeek API key |
| `OPENAI_API_KEY` | OpenAI API key |
| `ANTHROPIC_API_KEY` | Anthropic API key (API key path) |
| `GEMINI_API_KEY` | Google Gemini API key |
| `GROK_API_KEY` | xAI Grok API key |
| `GROQ_API_KEY` | Groq API key |

### Key files

| File | Purpose |
|------|---------|
| `~/.halcode/connections/*.json` | User provider overrides |
| `providers/*.json` | System provider definitions |
| `~/.halcode/history.json` | Saved conversation history |

### IPC socket namespace

| Socket | Tool |
|--------|------|
| `@halcode/Read` | Read |
| `@halcode/Head` | Head |
| `@halcode/LS` | LS |
| `@halcode/Write` | Write |
| `@halcode/Edit` | Edit |
| `@halcode/Bash` | Bash |
| `@halcode/Find` | Find |
| `@halcode/Grep` | Grep |
| `@halcode/Git` | Git |
| `@halcode/WebFetch` | WebFetch |
| `@halcode/JS` | JS |
| `@halcode/MCP` | MCP |
| `@halcore/Agent` | Agent |
| `@halcore/Pgmem` | Pgmem |
| `@halcore/Relmem` | Relmem |

---

*Document version 1.0.0 — Generated from HalCode9000.x source analysis.*
