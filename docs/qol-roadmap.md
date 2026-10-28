# HalCode9000 — Class-Leader QOL Roadmap

Prioritized list of quality-of-life features to move HalCode9000 from "works"
to "class leader" among coding agents. Grounded in the existing tree:
`docs/architecture.md` §17, `HalCode9000.md` "Phase 2", and the 15 persistent
`cc_*_ipc` workers that are currently idle during sequential dispatch.

---

## Tier 1 — trust features (table stakes)

### 1. Edit rollback / undo stack
Every `Write`/`Edit` records a before-image (or reverse patch), and the user
gets `/undo`, `/redo`, and a `Diff`-backed "review what changed this turn"
view.

- Hooks: `cc_edit_ipc` + `cc_write_ipc` (record before-image), `cc_diff_ipc`
  (already built), `CC_ChatLoop` (slash-command wiring).
- Why: "Can it un-break my repo" is the #1 thing users judge an agent on.
- Status: ✅ **undo/redo stack done** — `cc_undo_ipc` journal + `/undo`
  (and `/undo N`, `/undo list`, `/undo status`, `/undo clear`) + `/redo`
  (and `/redo N`) + `Undo` tool all wired. Every Write/Edit records a
  before-image under `~/.halcode/undo/`; undo pushes an after-image onto a
  symmetric `~/.halcode/undo/redo/` journal (so `/redo` can re-apply it and
  `/undo` can then un-do it again); any new Write/Edit invalidates pending
  redos. Still open: the `Diff`-backed "review what changed this turn" view.

### 2. Auto-compaction (already planned as 17.5)
Go past the current "context at N% — checkpoint parked" cliff. At ~70%,
silently summarize the oldest turns, park the summary in the memory
plugin, and continue without user intervention.

- Hooks: context-window accounting in the main loop.
- Why: Claude Code truncates and loses the thread; seamless rollover is a
  real differentiator.

---

## Tier 2 — differentiators

### 3. Cross-session search (`/search`)
Session logs and decisions are already parked for search.
Expose that as a slash command to answer "what did we decide about X last week"
across sessions.

- Hooks: `CC_ChatLoop` slash-command table.

### 4. Parallel tool dispatch (17.4)
When a turn returns multiple independent tool calls, run them across the
persistent workers instead of sequentially.

- Hooks: the IPC worker pool (15 workers), the turn-dispatch loop.
- Why: big wall-clock latency win; looks instantly "fast."

### 5. Native cost/token meter
Live status-bar readout: tokens in/out, $/session, projected spend,
per-provider.

- Hooks: `providers/*.json` (8 pricing configs), token accounting in the loop.

---

## Tier 3 — power features

### 6. User-authorable skills + slash commands
Make the `skills/*.md` directories user-writable and discoverable from the
TUI.

- Hooks: `Skills op=list/read`, TUI menu.

### 7. Auto-verify loop
After each edit, auto-run `./analyzer.x` (or the LSP) on the touched
`.ailang` file and iterate until green.

- Hooks: `AilangLSP`, `analyzer.x`, `ailang.x`.

### 8. Provider failover
On rate-limit/5xx, hot-swap to the next provider in `providers/*.json`.

- Hooks: 8 provider backends, the provider-selection path.

### 9. Multi-turn sub-agents (17.2)
Background sub-agents that persist across turns.

- Hooks: `Agent` tool, `cc_agent_ipc`.

---

## Architectural debt that gates several of the above

**Memory-plugin deadlock (rule 17).** The memory plugin is single-threaded.
A held call blocks other agents from storing a result, which kills them on
timeout. Fix that before investing in multi-turn sub-agents or streaming
results.
