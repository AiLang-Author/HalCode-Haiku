# HalCode — QOL Roadmap (all versions)

Prioritized quality-of-life features to move HalCode from "works" to
"class leader" among coding agents. This one roadmap covers every
HalCode version. The same file lives in every repo; edit it in
HalCode9000 and copy it to the others.

Status audited against the code on 2026-11-05.

## Versions

| Version | Repo | Front end | Platform |
|---|---|---|---|
| HalCode9000 | `AiLang-Author/HalCode9000` | Terminal UI (`UI.ailang`) | Linux |
| HalCodeGTK | `AiLang-Author/HalCodeGTK` | AppDesk + GTK blit shell | Linux |
| HalCode-Haiku | `AiLang-Author/HalCode-Haiku` | AppDesk + native Haiku window | Haiku (native work in `Platform/*Haiku`) |
| HalBot | `/home/bob/HalBot` | web page + MCP, headless guest | Linux guest VM |

Status codes in the tables: **done**, **partial**, **built, not wired**,
**open**, **n/a**.

---

## Step 0 — one shared core (gates everything below)

The repos are copies of one code base that have drifted in both
directions. HalBot carries a fourth copy (`HalCode9000.ailang`,
`cc_tools`, `backends`) and gets the same treatment:

- HalCode-Haiku's committed tree is identical to HalCodeGTK. Its
  uncommitted work is the Haiku platform layer (`Platform/`).
- `HalCode9000.ailang` differs between HalCode9000 and HalCodeGTK by
  about 1,000 lines.
  - Only in GTK and Haiku: host mode (`CC_HostCtlOpen`,
    `CC_HostShutdown`, `CC_HostArmSig`), `CC_StatusReport`,
    `CC_ParkDigest`, `CC_FormatSessionList`, `CC_ResolveWorkerSpec`,
    `CC_ProvFromJSON`, `CC_HttpStatusHint`, `CC_ReapChildren` and
    others.
  - Only in HalCode9000: newer tool fixes, for example `find -L` in
    Skills.
- 13 `cc_tools/*.ailang` workers differ between HalCode9000 and GTK.
- Even this roadmap had drifted.

Built three times, every item below would drift further. So:

1. **One canonical shared core in HalCode9000:**
   - agent loop and turn dispatch;
   - `IPCDispatch`, `History`, `Auth`, `backends/`, `providers/`;
   - every `cc_tools` worker;
   - the `Platform/` interface with its Linux and Haiku
     implementations.
2. **Each repo keeps only its own front end and platform selection:**
   - HalCode9000: the terminal UI;
   - HalCodeGTK: the desk and GTK shell;
   - HalCode-Haiku: the desk, the Haiku window and the Haiku platform
     selection;
   - HalBot: its web page, MCP server and guest setup.
3. **One-way sync script** that copies the shared core from HalCode9000
   into the others. Shared files are never edited in GTK or Haiku.
4. **Merge in both directions once:**
   - GTK-only functions go into the core;
   - 9000-only fixes go into GTK and Haiku through the sync.
   - Gate: all three build. The Linux binaries of GTK and Haiku behave
     the same as before, checked with the HalCode9000 tool tests. The
     Haiku native gate (phase 4 of `haiku-native-plan.md`) still
     passes.

Everything below is then implemented once, in the core, and ships to
every version through the sync. Only front-end or platform pieces are
written per version.

---

## Tier 1 — trust features (table stakes)

### 1. Edit rollback / undo stack

Every `Write`/`Edit` records a before-image, with `/undo` and `/redo`
plus a Diff-backed "review what changed this turn" view.

| | 9000 | GTK | Haiku |
|---|---|---|---|
| undo/redo stack | done | done | done |
| "review this turn" view | open | open | open |

- Done: the `cc_undo_ipc` journal; `/undo`, `/undo N`, `/undo list`,
  `/undo status`, `/undo clear`; `/redo`, `/redo N`; the `Undo` tool.
  Before-images are kept in `~/.halcode/undo/`, with a symmetric redo
  journal. A new Write or Edit clears pending redos.
- Open: a `/changes` view that lists the files touched this turn, using
  `cc_diff_ipc`. Core work; each front end only renders it.

### 2. Auto-compaction

Past the "context at N%" cliff: at about 70%, summarize the oldest
turns, park the summary in the memory plugin, and continue without user
intervention.

| | 9000 | GTK | Haiku |
|---|---|---|---|
| manual `/compact` | done | done | done |
| context % shown | done | done | done |
| automatic rollover | open | open | open |

- Hooks: `CC_CompactSession`, `Pgmem op=compact` (exists), context
  accounting (`UILayout.ctx_pct`), the turn loop.
- Core work. Needs a working memory plugin. On Haiku, Pgmem operations
  that need postgres currently answer "unavailable", so auto-compaction
  there needs a fallback, such as parking to a local file.

---

## Tier 2 — differentiators

### 3. Cross-session search (`/search`)

Answer "what did we decide about X last week" across sessions.

| | 9000 | GTK | Haiku |
|---|---|---|---|
| `/search` | open | open | open |

- Existing: `/sessions` and `/resume`, and parked session digests.
- Hooks: the slash-command table, `Pgmem op=search` (exists; session
  logs and decisions are already parked with full-text search). Core
  work.

### 4. Parallel tool dispatch

When a turn returns several independent tool calls, run them at the
same time instead of one after another.

| | 9000 | GTK | Haiku |
|---|---|---|---|
| parallel dispatch | built, not wired | built, not wired | open (CCFan compiled out) |

- Existing: the `CCFan` thread pool (`CCFan_Init`, `CCFan_RunBatch`,
  `CCFan_Shutdown`). Only `CCFan_SelfTest` calls it; turn dispatch is
  still sequential. The join in `CCFan_Shutdown` has hung before.
- **Recommended design: process fan-out, no threads.** The tool workers
  are already separate processes:
  1. Send every independent call to its worker.
  2. Wait for all the replies: `poll` over the sockets on Linux, and
     `wait_for_objects` over the reply ports on Haiku.
  3. Put the results back in call order.
- This works on Haiku today, with no `spawn_thread` needed, and lets
  CCFan be retired.
- The wait is a `Platform.IPC` function, `PlatformIPC_WaitMany`, with a
  Linux and a Haiku implementation. The dispatch logic is core.
- Rules:
  - Only calls the model marked as independent run in parallel.
    `Write`, `Edit`, `Undo` and `Bash` on the same path stay ordered.
  - One worker instance handles one call at a time; a second call to
    the same tool waits or gets a second instance.

### 5. Native cost/token meter

A live readout of tokens in and out, cost for the session, projected
spend, and the split per provider.

| | 9000 | GTK | Haiku |
|---|---|---|---|
| per-response usage | partial (`Backend.PrintUsage`) | partial | partial |
| prices | open | open | open |
| live meter | open | open | open |

- **The provider files hold no prices.** `providers/*.json` (anthropic,
  deepseek, gemini, groq, ollama, openai, openrouter, xai) list models
  only. Earlier versions of this roadmap called them "pricing configs";
  they are not.
- Steps:
  1. Add per-model `price_in`, `price_out` and, where the provider has
     them, `price_cache_read` and `price_cache_write` (USD per million
     tokens) to the provider schema. `/refresh-models` must keep these
     fields.
  2. Collect usage from each backend's response into one core counter.
  3. Each front end renders the meter: the status bar in the TUI, the
     desk status line in GTK and Haiku.
- Unknown prices show as "?" instead of 0.

---

## Tier 3 — power features

### 6. User-authored skills and slash commands

| | 9000 | GTK | Haiku |
|---|---|---|---|
| Skills tool list/read | done | done (older; lacks `find -L`) | done (older) |
| user-writable skills dir | open | open | open |
| skills in the UI menu | open | open | open |

- Make `~/.halcode/skills/` user-writable and merge it with the shipped
  `skills/`; on a name clash, the user's copy wins.
- A skill can declare a slash command.
- The discovery and menu data are core. Each front end draws its own
  menu.

### 7. Auto-verify loop

After each edit to a `.ailang` file, run the analyzer or LSP on it and
iterate until it is clean.

| | 9000 | GTK | Haiku |
|---|---|---|---|
| auto-verify | open | open | open (blocked) |

- Hooks: `AilangLSP`, `analyzer.x`, the compiler.
- Make it opt-in (`/verify on`), with a maximum number of rounds per
  turn.
- On Haiku it is blocked by the Ailang tool. That tool calls a stale
  Linux `ailang.x`, never passes `--haiku`, and is not ported. The
  install task fixes it.
- Also check the `analyzer.x` failure reported on the guest (it prints
  its usage message and exits 1 on valid input) on Linux, so it is
  known whether it affects every version.

### 8. Provider failover

On a rate limit, a 5xx error or a timeout, switch to the next
configured provider and model, and tell the user.

| | 9000 | GTK | Haiku |
|---|---|---|---|
| failover | open | open | open |

- Hooks: the backends, `CC_ProvFromJSON` and `CC_HttpStatusHint`
  (GTK and Haiku only today; they come into the core in step 0), and
  `providers/*.json`.
- Use an ordered failover list in the configuration, and fail over only
  to providers with a key present.
- A turn that has already streamed text is not retried on another
  provider without asking.

### 9. Multi-turn sub-agents

Background sub-agents that persist across turns.

| | 9000 | GTK | Haiku |
|---|---|---|---|
| multi-turn sub-agents | open | open | open |

- Hooks: the `Agent` tool and `cc_agent_ipc`.
- Blocked by the memory-plugin deadlock below.

---

## Architectural debt that gates several items

**Memory-plugin deadlock.** The memory plugin (`cc_pgmem_ipc`, with
its source in `halcode-plugins`) is single-threaded. A held `pickup` socket
blocks the agent daemon from parking its result, which kills agents on
timeout. Fix
this before items 9 and 2, and before streaming tool results.

- A queued, asynchronous result channel unlocks parallel agents,
  streaming tool output and background task completion. Several of the
  items above become nearly free once it is fixed.
- The fix lives in `halcode-plugins` and ships to every version.

---

## Order of work

1. Step 0: the shared core and the sync script.
2. In parallel, because none of them depend on step 0:
   - the memory-plugin deadlock (`halcode-plugins`);
   - price fields in the provider schema (data and schema only);
   - the `analyzer.x` check on Linux.
3. After step 0:
   - 4 (process fan-out);
   - 5 (meter);
   - 1 ("review this turn" view);
   - 8 (failover).
4. After the deadlock fix: 2 (auto-compaction), 3 (search), 9
   (sub-agents).
5. 6 and 7 at any point after step 0. Item 7 on Haiku comes after the
   install task.

---

## Appendix — task prompts

Ready-to-send prompts for the parallel work in "Order of work". Each one
stands alone, so any bot can take it. They also exist as separate files in
`HalCode9000/docs/tasks/`. Edit those first and regenerate this appendix.

### T1: shared-core merge map (step 0, analysis only)

#### Goal

- Produce the merge map for step 0 of `docs/qol-roadmap.md`: exactly
  what differs between the four HalCode code bases, and which version
  of each difference the shared core should keep.
- **This task is analysis only. It changes no source file.** The merge
  itself is a later task that works from this map.

#### Trees

- `/home/bob/HalCode9000`: the canonical core, terminal UI.
- `/home/bob/HalCodeGTK`: desk + GTK shell.
- `/home/bob/HalCode-Haiku`: desk + Haiku window.
  - Its committed tree (`git show HEAD:<file>`) equals HalCodeGTK.
  - Its working tree has uncommitted Haiku platform work in `Platform/`
    and the files that use it. Another bot is editing this tree right
    now, so read it but never write to it.
- `/home/bob/HalBot`: the bot. It also carries `HalCode9000.ailang`,
  `cc_tools`, `backends` and the other shared files.

#### Do

1. List every file that exists in more than one tree, and mark each
   one as:
   - **shared core:** agent loop, `IPCDispatch`, `History`, `Auth`,
     `backends/`, `providers/`, `cc_tools/`, `Platform/`;
   - **front end:** `UI.ailang`, `shell/`, desk, window;
   - **unclear:** say why.
2. For each shared-core file, diff the trees and classify each
   difference:
   - a feature or fix present in one tree only: name it, and say which
     tree has it;
   - a conflicting change to the same code: show both sides;
   - a front-end or platform difference sitting in a shared file:
     propose moving it behind `Platform/` or into the front end.
3. For `HalCode9000.ailang`, list the functions unique to each tree.
   Known so far: GTK and Haiku have the host-mode functions
   (`CC_HostCtlOpen`, `CC_HostShutdown`, `CC_HostArmSig`),
   `CC_StatusReport`, `CC_ParkDigest`, `CC_FormatSessionList`,
   `CC_ResolveWorkerSpec`, `CC_ProvFromJSON`, `CC_HttpStatusHint`,
   `CC_ReapChildren` and more. HalCode9000 has newer tool fixes, such
   as `find -L` in Skills. Complete the list for all four trees.
4. For each of the 13 `cc_tools` workers that differ between HalCode9000
   and GTK, state what differs and which version to keep.
5. Propose a sync script: which paths are copied from HalCode9000 into
   each other tree, and which are never touched there. Write the
   proposal; don't create the script.

#### Rules

- Read only. Don't edit, build, commit or push anything.
- Don't print the contents of `~/.halcode`, key files or provider keys.

#### Output

- Write `/home/bob/HalCode9000/docs/tasks/T1-merge-map-result.md` with:
  - the file classification table;
  - the per-file difference list, each with a keep decision or an open
    question;
  - the proposed sync script paths;
  - a count of open questions that need the owner.

### T2: memory-plugin deadlock

#### Goal

- Fix the memory plugin's single-threaded deadlock: a held `pickup`
  socket blocks the agent daemon from parking its result, and agents
  die on timeout.
- This gates roadmap items 2 (auto-compaction), 3 (search) and 9
  (sub-agents), and streaming tool results. See
  `/home/bob/HalCode9000/docs/qol-roadmap.md`, "Architectural debt".

#### Where

- Source: `/home/bob/halcode-plugins/cc_pgmem_ipc.ailang` (about 1,500
  lines). Design notes: `/home/bob/halcode-plugins/docs/DESIGN_PGMEM.md`.
- `halcode-plugins` is proprietary (`LICENSE-PROPRIETARY`). Don't copy
  its source into any public repo, and don't paste it into any external
  service.
- The HalCode trees also have a `cc_tools/cc_pgmem_ipc.ailang`. Find out
  how it relates to the plugin copy (same code, a stub or a fork), and
  report that.

#### Do

1. **Reproduce first.** Write a test that starts the plugin, holds a
   `pickup` connection open, and shows a second client's `park` timing
   out. Record the timings.
2. **Find the cause.** Identify exactly where the plugin blocks: accept
   loop, per-connection read, database call, or result write.
3. **Fix it** with the smallest change that removes the block.
   - Preferred: an event loop that multiplexes connections with `poll`,
     plus a queue for results, so one slow call never blocks
     another client's store.
   - Avoid threads unless they are clearly simpler. The Haiku build has
     no threads yet, and thread joins have hung before.
4. **Keep the wire protocol unchanged,** so existing workers and agents
   don't need to change.
5. **Re-run the test:** the second client's store must complete while
   the first call is held. Also run any existing Pgmem tests, and a
   park/pickup round trip.

#### Rules

- Don't replace `Ailang-Self-Hosting-/ailang.x`. Build with it into a
  scratch path.
- Don't commit or push. Don't touch the HalCode-Haiku tree; another bot
  is working in it.
- Don't print or log provider keys or database credentials.

#### Output

- Report:
  - the cause, with file and line;
  - the change made, as a diff summary;
  - the test before and after, with timings;
  - existing tests and the round-trip result;
  - how `cc_tools/cc_pgmem_ipc.ailang` relates to the plugin copy.

### T3: price fields for the cost meter

#### Goal

- Add per-model prices to the provider files, so roadmap item 5 (the
  cost/token meter) has data.
- This task covers the schema and data only. The meter itself comes
  after step 0.

#### Where

- Work only in `/home/bob/HalCode9000/providers/*.json`: anthropic,
  deepseek, gemini, groq, ollama, openai, openrouter, xai.
- Other trees get the change later through the step 0 sync. Don't edit
  them now.

#### Do

1. Add these optional fields to each model entry, in USD per million
   tokens:
   - `price_in`;
   - `price_out`;
   - where the provider charges for cache: `price_cache_read` and
     `price_cache_write`.
   Add a provider-level `prices_checked` date (YYYY-MM-DD) and
   `prices_source` (the URL of the provider's own pricing page).
2. Fill prices only from each provider's official pricing page, current
   on the day you check.
   - If a model's price can't be confirmed, leave its fields out. Don't
     guess.
   - Leave all prices out for Ollama (local); it costs nothing per
     token.
   - For OpenRouter, take prices from its models API, not from the
     upstream providers.
3. Make sure `/refresh-models` (`CC_RunModelScraper` and its scraper
   script) keeps the price fields when it rewrites a provider file. If
   it would drop them, fix it so it merges.
4. Check that every file still parses as JSON. Make sure HalCode still
   loads the providers: run `--mcp` initialize and `tools/list` once
   with the trusted compiler's build in a scratch path.

#### Rules

- Don't replace `Ailang-Self-Hosting-/ailang.x`. Don't commit or push.
- Don't put any API key into any file, and don't call paid model APIs.
  Reading public pricing pages and model-list endpoints is fine.

#### Output

- Report:
  - a table of provider, model, the four prices, and the source URL;
  - the models left without prices, and why;
  - whether the scraper had to be changed;
  - the parse and load check results.

### T4: analyzer.x usage failure on Linux

#### Goal

- On the Haiku guest, `analyzer.x` printed its usage message and
  exited 1 for valid input. Find out whether the same happens on Linux,
  and why.
- This decides whether roadmap item 7 (auto-verify) is blocked on every
  version, or only on Haiku.

#### Where

- Analyzer source and build: find them in
  `/home/bob/Ailang-Self-Hosting-`. Start from where `analyzer.x` is
  built, and from the `cc_ailang_ipc` worker that calls it
  (`/home/bob/HalCode9000/cc_tools/cc_ailang_ipc.ailang`).
- The guest copy was `/boot/home/analyzer.x` (428,362 bytes, built
  2026-11-04).

#### Do

1. On Linux:
   - build `analyzer.x` from the current tree into a scratch path, with
     the trusted `./ailang.x`;
   - run it the way `cc_ailang_ipc` runs it, on two or three valid
     `.ailang` files;
   - record the exit code and output.
2. If it fails on Linux, find the cause: argument parsing, reading
   `/proc/self/cmdline`, file open, or something else. Fix it if the fix
   is small and local, and explain it.
3. If it works on Linux, compare with how it runs on Haiku:
   - the guest copy is a Linux ELF, so it runs through the bridge;
   - the arguments reach it through the bridge's `/proc/self/cmdline`.
   Report the likely Haiku-only cause. Don't run anything on the Haiku
   guest; another bot is using it.

#### Rules

- Don't replace `Ailang-Self-Hosting-/ailang.x`. Don't commit or push.
- Don't run or touch the Haiku VM.

#### Output

- Report:
  - whether it fails on Linux: yes or no, with the exact command, exit
    code and output;
  - the cause;
  - any fix made;
  - what that means for auto-verify on each version.
