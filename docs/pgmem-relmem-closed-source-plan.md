# pgmem / relmem → closed-source plugin

> Status: **phases 0–4 done on 2026-10-24. Phase 5 not started.**
> Companion to `docs/repo-cleanup-plan.md` (decisions #1, #6, #7).
> Goal: pgmem + relmem become a saleable closed-source plugin; this repo stays
> clean MIT with no schema, no op lists, no "how to use" copy.

---

## Verified current state

Facts checked against the tree before the work, not assumed:

| Fact | Evidence |
|---|---|
| One source copy each | `cc_tools/cc_pgmem_ipc.ailang`, `cc_tools/cc_relmem_ipc.ailang` |
| Sources are gitignored and were **never** tracked | `.gitignore:2-4`; `git ls-files` → no `.ailang` hits |
| SCSL is **one line** per file | pgmem line 32, relmem line 26 (`Copyright 2026 Sean Collins, 2 Paws Machine and Engineering. SCSL.`) |
| Binaries are tracked and public | `cc_pgmem_ipc.x`, `cc_relmem_ipc.x` in `git ls-files` |
| Binaries embed **no** license string | `strings -a *.x \| grep -i -e scsl -e "2 Paws"` → none |
| Docs already leaked to public HEAD | `docs/DESIGN_PGMEM.md`, `skills/halcode/pgmem/SKILL.md`, `skills/halcode/relmem/SKILL.md` all tracked |
| Repo already pushed | `origin` = `github.com/AiLang-Author/HalCodeGTK.git`, `main` was `4b3692b`, in sync, before this work |
| `.bak` gap | `.gitignore` covered `cc_pgmem_ipc.ailang.bak` but **not** the relmem one |
| README advertises both | lines 16 and 37, before this work |

Consequence: the header rewrite is trivial (a line each). The real work is
Phase 2 — the design doc and two SKILL.md files were committed in `645d19c`
and were already on GitHub.

---

## Phase 0 — pre-flight

- [x] Add `cc_tools/*.ailang.bak` to `.gitignore` (relmem `.bak` is currently uncovered; an editor backup of the ops list would be stageable). Explicit glob is in place. `git check-ignore -v` still names the later global `*.bak` rule as the last match.
- [x] Confirm both tools still run from local builds. The binaries are at the repo root (`./cc_pgmem_ipc.x`, `./cc_relmem_ipc.x`), not under `cc_tools/`. Smoke: each connected, listened, then that pid was stopped. No host was running.
- [x] Snapshot before touching headers. Olympus CLI is not on PATH, so this was a file copy of the pre-header sources. Those copies stay gitignored and are not in the plugin commit.

## Phase 1 — proprietary header (local only, never committed)

Replace the single SCSL line in each file with:

```
// Copyright 2026 Sean Collins, 2 Paws Machine and Engineering.
// All rights reserved. Proprietary and confidential.
// Not licensed for redistribution. Commercial license available on request.
```

- [x] `cc_pgmem_ipc.ailang` line 32 → block above
- [x] `cc_relmem_ipc.ailang` line 26 → block above
- [x] Keep the descriptive comment block above it in **pgmem** — it documents the wire ops; it belongs in the plugin repo, not in a public diff. Diff against the snapshot is the header only.
- [x] Header-only change: `analyzer.x` reported 0 errors on both. Exit code 1 is pre-existing warnings. No rebuild.
- [x] Verify: `grep -c SCSL` → 0 on both files. Sources stay gitignored and are not in this commit.

## Phase 2 — stop the docs bleed from HEAD

- [x] `git rm docs/DESIGN_PGMEM.md skills/halcode/pgmem/SKILL.md skills/halcode/relmem/SKILL.md`
- [x] Those three files were copied into the plugin repo before the delete. `cmp` matched.
- [x] README lines 16 and 37 stripped (pgmem/relmem dropped from the optional-deps and setup copy)
- [x] Audit of `docs/architecture.md` and `docs/qol-roadmap.md`: feature chapters and schema names removed. Tool names stay where the public binary list already names them. The same strip was applied on HalCode9000 so that push does not leave the chapters on its default branch. `HalCode9000.md` lost the one row that listed the protocol.
- [x] Verify: `git ls-files | grep -iE 'pgmem|relmem'` → the two `.x` files, plus this plan. This plan is an intentional extra match. Do not delete it to make the grep quiet.

## Phase 3 — decide what to do about history

The docs are public at `645d19c` and were already pushed. Deleting from HEAD does not unpublish old commits.

- [x] Decision: **(a) Accept.** Sources never leaked; only design prose did. Removing the HEAD copy stops future readers of the default branch. No `git filter-repo`. No force-push.
- [x] (b) not taken. No fresh-clone check for a rewrite, because there is no rewrite.
- [x] Recorded 2026-10-24 so this is not re-litigated. Same decision on HalCode9000: the three files leave HEAD, history stays.

## Phase 4 — plugin repo

- [x] Private repo `AiLang-Author/halcode-plugins`
- [x] Landed: both sources, `LICENSE-PROPRIETARY`, `build.sh`, the three docs from Phase 2
- [x] `cc_tools.json` registration stays in the public repo (it names the tool, not the source)
- [x] Install path documented only in the plugin repo. The public README does not advertise it.
- [x] Licensing mechanics: honor system until a per-machine key or a signed build exists. Written in the plugin `LICENSE-PROPRIETARY`.

## Phase 5 — binaries (only when actually selling)

- [ ] `git rm --cached cc_pgmem_ipc.x cc_relmem_ipc.x`, add to `.gitignore`
- [ ] Publish them as release artifacts instead
- [ ] Verify a clean clone still builds/runs after the plugin install step

---

## Out of scope / never in this repo

- DB schema, SQL, table names
- The op list and wire protocol
- "How to use pgmem" copy of any kind
- This plan mentions no schema detail on purpose — keep it that way

Left on purpose, not part of the Phase 2 delete list: `config/system_prompt.txt`
and `skills/halcode/agent-orchestration/SKILL.md`. The running agent loads them.
They are not a second copy of the design doc.
