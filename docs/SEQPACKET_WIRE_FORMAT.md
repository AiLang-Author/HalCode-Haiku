# HalCode9000 SEQPACKET Wire Format v1.0

All HalCode9000 tools communicate over **SEQPACKET** (SOCK_SEQPACKET) Unix domain
sockets. This spec defines the request/response envelope, framing, error
conventions, and the API discovery mechanism.

---

## 1. Transport

| Property      | Value                                           |
| ------------- | ----------------------------------------------- |
| Socket type   | `SOCK_SEQPACKET` (AF_UNIX, type=5 on Linux)    |
| Socket path   | `/tmp/ailang_cctools/<ToolName>.sock`           |
| Framing       | One JSON object per SEQPACKET message           |
| Encoding      | UTF-8                                           |
| Auth          | FS permissions on `/tmp/ailang_cctools/` (0700) |

**Why SEQPACKET?** Each `sendmsg`/`recvmsg` pair preserves message boundaries,
saving us from delimiter scanning. The kernel ensures one `recvmsg` = one
`sendmsg`. No `\n` framing, no `Content-Length` headers inside our protocol.

---

## 2. Message Envelope

Every message — request or response — is a single JSON object with a `method`
field.

### 2.1 Request

```json
{
  "method": "call",
  "id": "<uuid-or-unique-string>",
  "args": { ... tool-specific named parameters ... }
}
```

| Field    | Type   | Required | Notes                                       |
| -------- | ------ | -------- | ------------------------------------------- |
| method   | string | yes      | Always `"call"` for a tool invocation       |
| id       | string | yes      | Opaque identifier echoed in the response    |
| args     | object | yes      | Keys match the tool's input schema          |

### 2.2 Response (success)

```json
{
  "method": "result",
  "id": "<echoed-id>",
  "ok": true,
  "content": "<tool output as a single string>"
}
```

| Field    | Type   | Required | Notes                                              |
| -------- | ------ | -------- | -------------------------------------------------- |
| method   | string | yes      | Always `"result"`                                  |
| id       | string | yes      | Echo of the request `id`                           |
| ok       | bool   | yes      | `true`                                             |
| content  | string | no       | Tool output; absent for side-effect-only tools     |

### 2.3 Response (error)

```json
{
  "method": "result",
  "id": "<echoed-id or empty>",
  "ok": false,
  "error": "<human-readable error message>"
}
```

| Field    | Type   | Required | Notes                                              |
| -------- | ------ | -------- | -------------------------------------------------- |
| method   | string | yes      | Always `"result"`                                  |
| id       | string | no       | Echo of request `id`; absent if parse failed       |
| ok       | bool   | yes      | `false`                                            |
| error    | string | yes      | Human-readable error description                   |

### 2.4 Schema Discovery

A client can request a tool's input schema without invoking it:

**Request:**
```json
{
  "method": "schema",
  "args": {}
}
```

**Response:**
```json
{
  "method": "schema_response",
  "schema": {
    "name": "<ToolName>",
    "description": "<...>",
    "input_schema": {
      "type": "object",
      "properties": { ... },
      "required": [ ... ]
    }
  }
}
```

The `schema` object is a valid **Claude Code tool schema** (MCP-compatible
`input_schema` shape). See Section 4.

---

## 3. Connection Lifecycle

```
CLIENT                              SERVER (long-running daemon)
  |                                       |
  |-- socket() SOCK_SEQPACKET ----------->|
  |-- connect() ------------------------->|
  |                                       |
  |-- sendmsg(req_json) ----------------->|
  |                                       |-- JSON parse + validate
  |                                       |-- dispatch handler
  |                                       |-- sendmsg(resp_json)
  |<------- recvmsg(resp_json) ----------|
  |                                       |
  |-- close() --------------------------->|
```

- **One request = one response.** No pipelining. No streaming.
- The server processes requests sequentially within one connection.
- The server closes the connection after the response is sent (most tools), or
  after the client disconnects (long-lived listeners).
- The server is a persistent daemon. It handles multiple sequential connections.

---

## 4. Tool Schema Format

Each tool's schema is discoverable via the `"schema"` method. The response
format mirrors the MCP `input_schema` convention:

```json
{
  "name": "Bash",
  "description": "Run a shell command via /bin/sh ...",
  "input_schema": {
    "type": "object",
    "properties": {
      "command": {
        "type": "string",
        "description": "Shell command to execute"
      },
      "timeout_secs": {
        "type": "integer",
        "description": "Wall-clock timeout in seconds"
      }
    },
    "required": ["command"]
  }
}
```

---

## 5. Error Conventions

| Scenario                     | `ok`   | `error` message                    | `id`              |
| ---------------------------- | ------ | ---------------------------------- | ----------------- |
| Malformed JSON               | false  | `"invalid JSON"`                   | absent            |
| Missing `method` field       | false  | `"missing method"`                 | absent            |
| Unknown `method` value       | false  | `"unknown method"`                 | absent            |
| Missing required args        | false  | `"missing required arguments"`     | echoed            |
| Invalid argument type        | false  | `"invalid argument: <field>"`      | echoed            |
| Internal tool failure        | false  | tool-specific message              | echoed            |
| Tool execution success       | true   | N/A                                | echoed            |

---

## 6. Implementation Notes

### 6.1 Why not JSON-RPC?

Standard JSON-RPC 2.0 requires `jsonrpc: "2.0"`, named-param objects, and
error codes. HalCode9000 uses a simplified envelope because:

- Claude Code's native tool envelope already uses `method`/`id`/`ok`/`error`.
- The schema method provides the same discovery as MCP's `tools/list`.
- SEQPACKET framing eliminates the need for `Content-Length` headers inside
  our protocol (unlike stdio-based MCP servers, which *do* use them — see
  MCP bridge spec).

### 6.2 MCP Bridge

The `cc_mcp_ipc.x` tool is a *bridge*: it accepts the same SEQPACKET envelope,
then translates to standard MCP JSON-RPC over stdio for the child MCP server.
The bridge handles `Content-Length` framing on the MCP side transparently.

### 6.3 Maximum Message Size

Default: 50,000 bytes per message (tool-configurable). SEQPACKET's kernel
buffers handle up to `wmem_max` (typically 208 KB on Linux).

---

## 7. Tool Index

| Tool           | Socket Path                              |
| -------------- | ---------------------------------------- |
| Bash           | `/tmp/ailang_cctools/Bash.sock`          |
| Read           | `/tmp/ailang_cctools/Read.sock`          |
| Write          | `/tmp/ailang_cctools/Write.sock`         |
| Edit           | `/tmp/ailang_cctools/Edit.sock`          |
| Head           | `/tmp/ailang_cctools/Head.sock`          |
| LS             | `/tmp/ailang_cctools/LS.sock`            |
| Find           | `/tmp/ailang_cctools/Find.sock`          |
| Grep           | `/tmp/ailang_cctools/Grep.sock`          |
| Git            | `/tmp/ailang_cctools/Git.sock`           |
| Diff           | `/tmp/ailang_cctools/Diff.sock`          |
| Stat           | `/tmp/ailang_cctools/Stat.sock`          |
| Wc             | `/tmp/ailang_cctools/Wc.sock`            |
| Du             | `/tmp/ailang_cctools/Du.sock`            |
| Relmem         | `/tmp/ailang_cctools/Relmem.sock`        |
| Pgmem          | `/tmp/ailang_cctools/Pgmem.sock`         |
| MCP            | `/tmp/ailang_cctools/MCP.sock`           |
| Agent          | `/tmp/ailang_cctools/Agent.sock`         |
| Ailang         | `/tmp/ailang_cctools/Ailang.sock`        |
| AilangLSP      | `/tmp/ailang_cctools/AilangLSP.sock`     |
| Olympus        | `/tmp/ailang_cctools/Olympus.sock`       |

---

*Version: 1.0 — 2026. Licensed under MIT.*
