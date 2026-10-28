# HalCode GUI — chrome shell over the AILang kernel

> Status: **phase 1 started.** Thin GTK blit host lives in `shell/`.
> Kernel stays AILang. Same kernel on Linux (GTK) and Haiku (BeAPI).

**One line:** two processes — a thin `halcode_shell_*` (native window chrome +
Cairo/BeAPI blit) and `HalCode9000.x` as the kernel running AppDesk MDI +
DocView / DocSess / DocStore. Pixels start as CAD’s `frame.raw` + `gen.txt`,
then `ShmCanvas`. Input over abstract-socket JSON (`@halcode/*` discipline),
not `cmd.txt`. Tools, History, backends, `--agent`, `--mcp` do not change.

---

## 1. The pattern already exists

This is not greenfield. CAD is the proof:

- `CAD/host/cad_shell_gtk.cxx` (and `cad_host_x11.c`) — GTK/X11 window =
  chrome + blit only; AILang owns rendering.
- Kernel writes: `meta.bin` (w/h/pitch), `frame.raw` (BGRA), `gen.txt`
  (frame-ready), `status.txt` / `notice.txt`.
- Host writes: `cmd.txt` (orbit / click / hover / quit) with a busy-wait guard.
- Host loop: poll `gen.txt` → load frame → Cairo ARGB32 → `GtkDrawingArea`
  → `gtk_widget_queue_draw`. Input → `write_cmd`. ~12 ms tick.

HalCode-as-GUI-app is that contract with a chat/editor kernel instead of CAD.

---

## 2. What exists today

**HalCode (presentation to replace in GUI mode)**

- `HalCode9000.ailang` — SSE loop → `CC_AnimTick` → tool dispatch.
- `UI.ailang` — ANSI/raw-mode TUI. `tui-cleanup.md`: no widget tree, no dirty
  region, no front/back buffer; the terminal *is* the display.
- `cc_*_ipc.x` workers, `backends/`, `IPCDispatch`, `History`, `Auth`.
- Modes: TUI (default), `--agent` (headless), `--mcp` (stdio JSONL).

**AILang display stack (reuse, do not rewrite)**

- `Display/System/Library.SysDisplay` — display server, floats, focus.
- `Display/Window/Library.WinManager` — windows, geometry, `CanvasState`
  with `SHM_PTR` for IPC pixel streaming.
- `Applications/Library.AppDesk` — MDI, 42 floating doc windows inside one
  host blit. Header: *“no compositor, no GTK child windows.”*
- `Display/Content/` — `Document`, `DocView`, `DocSess`, `DocStore`,
  `Library.Editor`.
- `Display/UI/Library.Auckland` + `Library.AppHost` — markup → widget tree.
- `Library.ShmCanvas` — `/dev/shm/ailang_canvas_<win_id>`, BGRA.
- `Library.MessagePort` / `MessageTypes` / `MessageTranslate` — host-agnostic
  messages (BeAPI / Wayland / X11 / Qt).

---

## 3. Target split

```
┌─────────────────────────────────────────────────────────────┐
│  halcode_shell_gtk  (thin C/C++ GTK3 host; BeAPI twin later)│
│  GtkWindow / BWindow                                        │
│   ├─ menu bar      (native chrome only)                     │
│   ├─ optional status strip                                  │
│   └─ drawing area ── blits kernel framebuffer               │
│  keys / mouse / IME ──▶ socket JSON                         │
└──────────────────────────────┬──────────────────────────────┘
                               │  frame.raw + gen.txt  (then ShmCanvas)
                               │  @halcode/shell  JSON  (not cmd.txt)
┌──────────────────────────────▼──────────────────────────────┐
│  HalCode9000.x  — ALL rendering + agent logic               │
│  SSE → backends → cc_*_ipc                                  │
│  SysDisplay / WinManager / AppDesk                          │
│   └─ N floating docs into one DSurface                      │
│  Auckland + DocView + DocSess + DocStore                    │
│   └─ composit → BGRA → frame.raw + gen.txt                  │
└─────────────────────────────────────────────────────────────┘
```

**Chrome split**

- **Native shell owns app-level chrome only:** outer frame, title, menu bar,
  optional status strip. Nothing else.
- **AILang owns every document window’s chrome:** title bar, close, z-order,
  resize, drag, mode buttons — AppDesk / WinManager.

That matches AppDesk’s intent and keeps DocView / DocSess / DocStore in AILang.

`--agent` and `--mcp` stay headless. ANSI `UI.ailang` stays as `--tui` fallback
only; GUI mode does not port the ANSI path.

---

## 4. Multi-document: MDI in one native window

**Default (A):** one drawing area; AppDesk draws floating document windows
inside it. Drag / resize / z-order / close already exist. Zero new windowing.

**Later (B):** real OS windows per doc via WinManager / SysDisplay — escape
hatch (“detach”), not the default. Contradicts “GTK chrome only” if it is
the day-one path.

**Document types**

| Document | Backing |
|---|---|
| Conversation / agent chat | DocView + streamed tokens |
| File editor | Display/Content Editor + DocSess |
| Diff | DocView + diff renderer |
| Terminal / Bash | DocView, monospace |
| Memory browser (pgmem / relmem) | DocView or AppHost |
| Mascot / tool-call log | Auckland or AppDesk chrome |

Each window: `DocSess` + `WIN_ID` + `NODE_ID` (`DocSess_StampWin` /
`DocSess_StampJob`).

Tabs vs floating: AppDesk is floating MDI. A tab strip (in-canvas or native)
is an open question, not a requirement to start.

---

## 5. Transport

**Pixels, kernel → shell**

1. Ship **file protocol** first: `frame.raw` + `gen.txt` (CAD verbatim).
   ~12 ms poll is fine for chat.
2. Then **`Library.ShmCanvas`** for zero-copy.
3. Skip Vulkan for text.

**Input, shell → kernel**

- Do **not** use `cmd.txt` for HalCode. CAD’s vocabulary is tiny (`orbit`,
  `click`); we need Unicode, IME, paste, key repeat. Busy-wait `cmd.txt` is
  racy under typing.
- Use **abstract Unix socket + JSON**, same as `@halcode/*` and SysDisplay.
- `MessagePort` later if we want one host protocol for Wayland/BeAPI/Qt.

**Input semantics:** GTK/BeAPI send text + control keys (IME stays in the
shell). AILang `Editor` / `TextRegion` owns the buffer. Do not have the
kernel read raw evdev while GTK owns the window.

---

## 6. What does not change

- `cc_*_ipc.x`, backends, IPCDispatch, History, Auth, pgmem, relmem.
- `--agent` / `--mcp`.
- `@halcode/*` tool sockets.

Only `UI.ailang`’s presentation layer is replaced in GUI mode.
`UI.ChatPrint` / `ChatTag` / `ToolCallStart` become DocView appends.

---

## 7. Phased path (not today)

1. Clone CAD host → `halcode_shell_gtk`. Static hello frame.
2. Stub render: `UI.Init` / `ChatPrint` → `DSurface` → `frame.raw`. Agent
   loop + tools untouched.
3. AppDesk: one floating window per conversation; mouse over the socket.
4. DocSess per window, DocView for chat/editor, DocStore for persist.
5. `cmd.txt` → socket JSON; `frame.raw` → ShmCanvas.
6. Auckland for mascot/status/tool chrome; IME polish.

Haiku = same kernel, BeAPI blit shell (~3k lines of chrome), not a HalCode
port.

---

## 8. Open questions (settle before Phase 3)

1. **Tabs vs floating MDI** — floating is the AppDesk default; tabs optional.
2. **Who is parent** — CAD makes the kernel parent and spawns the shell.
   Keep that unless we have a reason not to.
3. **Status bar** — GTK strip vs in-canvas (`DashBar` argues not GTK chrome).
4. **Daemon-over-IPC vs in-process library** — pick one. Mixed models kill
   the Haiku/Linux port story. Recommendation: two processes, kernel parent,
   same as CAD.

---

## 9. Decision log

| # | Decision | Status |
|---|---|---|
| 1 | Kernel stays AILang; chrome shells are thin blit hosts | firm |
| 2 | Default = AppDesk MDI inside one native window | firm |
| 3 | Pixels = CAD `frame.raw` first, then ShmCanvas | firm |
| 4 | Input = socket JSON; GTK/BeAPI own IME | firm |
| 5 | `--agent` / `--mcp` stay headless | firm |
| 6 | Linux shell = GTK; Haiku shell = BeAPI | firm |
| 7 | Do not invent a new BSP/cell-grid kernel | firm |
| 8 | Phase 1: `shell/halcode_shell_gtk` + CAD `frame.raw` hello | in progress |
