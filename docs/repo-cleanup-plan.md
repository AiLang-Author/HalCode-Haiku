# HalCode9000 repo sanitization plan

> Status: **plan** — decisions locked 2026-09-09. Execute in the phases below.
> Origin: retarget to GitHub (`AiLang-Author/HalCode9000`). Codeberg is dead.
> UI/GTK: **new repo fork**, not this tree.

**Never `git add`:** `cc_tools/cc_pgmem_ipc.ailang`,
`cc_tools/cc_relmem_ipc.ailang`, or any `.bak` of those.

---

## Decisions (locked)

| # | Decision | Lock |
|---|---|---|
| 1 | pgmem / relmem **sources** | **private** — stay gitignored. ~$5 saleable plugins later. Not open core. |
| 2 | Tool sources in tree | **keep all `cc_tools/*.ailang` except pgmem/relmem.** That includes `cc_ls_ipc` and `cc_js_ipc`. |
| 3 | Prebuilts (`.x`) in git | **keep** until GitHub Releases exist. Delete only stray `hal_cc_*` names and `Beta1.zip`. |
| 4 | License | **DONE (MIT).** `LICENSE` added, `License SCSL.md` removed, HalCode + `cc_tools` headers flipped. pgmem/relmem, Packager, and `skills/ailang` left SCSL. |
| 5 | Packager tree | **delete `Packager/`** from this repo. Compile uses `$AILANG_ROOT/Packager`. Keep `cc_packager_ipc`. |
| 6 | pgmem / relmem **docs** | **delete from this repo.** `docs/DESIGN_PGMEM.md`, `skills/halcode/pgmem/`, `skills/halcode/relmem/`. Strip README + architecture feature copy. No schema, no SQL, no “how to use” in public. |
| 7 | pgmem / relmem **binaries** | **keep `.x` in git for now** (you still run them locally). README will not advertise them. Untrack when you actually sell the plugin. |
| 8 | `intrusivethoughts.json` | **keep in the release.** It is the bottom-scroll quote file (`CC_LoadQuotes`). Remove it from `.gitignore`. |
| 9 | JS tool | **keep.** Slow-burn, parked ~69% test262. Source + `cc_js_ipc.x` stay. Do **not** add to `cc_tools.json` until it is ready. Do **not** delete `hal_cc_js_ipc.x` thinking it is the JS tool — that name is a leftover. |
| 10 | Remote | **GitHub** `https://github.com/AiLang-Author/HalCode9000.git`. Current `origin` still points at Codeberg. |
| 11 | UI / GTK | **new repo fork.** No GTK/MDI code in this tree. `docs/gui-mdi-design.md` can stay as a pointer until the fork exists. |

---

## Clarification: `hal_cc_*` vs `cc_ls` / `cc_js`

Phase 1 deletes **old leftover binaries**, not the tools:

| File | What it is | Action |
|---|---|---|
| `cc_ls_ipc.ailang` + `cc_ls_ipc.x` | Real LS tool (in `cc_tools.json`) | **keep** |
| `cc_js_ipc.ailang` + `cc_js_ipc.x` | Real JS tool, parked ~69% test262 | **keep**, not registered yet |
| `hal_cc_ls_ipc.x` | May 21 leftover, old name | **delete** |
| `hal_cc_js_ipc.x` | May 21 leftover, old name | **delete** |

`build.sh` used to install as `hal_cc_*`. That naming is dead. Never install as `hal_cc_*` again.

---

## License truth (so MIT is not a surprise)

MIT is **not** already consistent:

- README + `setup.sh` → MIT
- `HalCode9000.ailang`, `UI.ailang`, `IPCDispatch.ailang`, `cc_tools/*.ailang`, `build.sh` → SCSL headers
- Only license file on disk → `License SCSL.md` (no-fork, no-commercial)

Phase 2/3: add `LICENSE` (MIT), remove `License SCSL.md`, rewrite `SCSL` headers to MIT. Do not touch pgmem/relmem sources (they are gitignored).

---

## What is wrong (short)

Three install stories fight:

1. README: clone GitHub → `./setup.sh` → run prebuilt `.x`
2. `build.sh`: `ailang.x` on PATH, `cd` compiler tree, compile this repo, copy `.x` here
3. Stale docs: `Applications/ClaudeCode`, `/mnt/c/Users/Sean/Documents/AILangSH`, fictional `src/`

`setup.sh` is a **runtime wizard** (Postgres, Olympus, keys), not a compiler installer.
`build.sh` does not create `$AILANG_ROOT/Applications/HalCode9000` and lists 11 core
tools while `cc_tools.json` has 26.

Worker counts in the wild: 7 / 15 / 23 / 26 / 27. MCP: README says `cc_mcp_ipc.x`;
runtime is `HalCode9000.x --mcp`.

Local `main` is 8 commits ahead of Codeberg origin. GitHub last push is 2026-06-02
(older still). Sanitize on top of local `main`. Do not reset.

---

## Phase 0 — remote (no commit)

```
git remote set-url origin https://github.com/AiLang-Author/HalCode9000.git
```

Do not push until the sanitize commits exist. GitHub `main` is behind this tree.

---

## Phase 1 — junk (one commit)

Delete:

- `Beta1.zip`
- `hal_cc_js_ipc.x`, `hal_cc_ls_ipc.x`  (leftover names only)
- `__pycache__/`
- `skills/.claude-plugin/marketplace.json`

Keep:

- `intrusivethoughts.json` (un-ignore; leave tracked)
- `cc_ls_ipc.x` / `cc_ls_ipc.ailang`
- `cc_js_ipc.x` / `cc_js_ipc.ailang`
- `cc_pgmem_ipc.x` / `cc_relmem_ipc.x` (binaries; sources stay ignored)

Gitignore:

- **Remove** `intrusivethoughts.json`
- **Keep** pgmem/relmem source ignore lines
- **Add** `__pycache__/`, `*.pyc`, `nohup.out`, `*.bak`, `*.zip`

Do **not** add `*.x` to gitignore until Releases exist.
Do **not** fold dirty HalCode source (`HalCode9000.ailang`, `History.ailang`, `UI.ailang`, …) into this junk commit.

---

## Phase 2 — license + build.sh + setup.sh (one or two commits)

License:

- Add `LICENSE` (MIT, Copyright 2026 Sean Collins, 2 Paws Machine and Engineering)
- Delete `License SCSL.md`
- Flip `SCSL` → `MIT` in HalCode + tool source headers and `build.sh`

`build.sh`:

- Fail with the exact `ln -sfn` if `$AILANG_ROOT/Applications/HalCode9000` is not this tree
- Name the compiler-repo installer `install_compiler.sh` (not a phantom script here)
- Tool list = `cc_tools.json` (+ pgmem/relmem **only if private sources exist locally**)
- Still compile `cc_js_ipc` even though it is not in `cc_tools.json`
- Never install as `hal_cc_*`
- Keep `fuser` refuse-overwrite of running binaries

`setup.sh`:

- Binary checklist = `cc_tools.json`
- Missing binaries: “use shipped `.x` or `./build.sh`” — no Sean AILangSH loop
- MCP: `./HalCode9000.x --mcp`
- `--no-system` to skip apt / bashrc / Olympus
- MIT header (already)

---

## Phase 3 — docs (one commit)

**Keep:** `README.md` (rewrite), `docs/architecture.md` (rewrite to this tree, **no** pgmem/relmem internals), `docs/gui-mdi-design.md` (pointer only), this file, `docs/js-engine-design.md` (JS is parked, not dead).

**Delete:**

- `docs/DESIGN_PGMEM.md`
- `skills/halcode/pgmem/`
- `skills/halcode/relmem/`
- `HalCode9000.md`, `API.md`, `tui-cleanup.md`
- `docs/SEQPACKET_WIRE_FORMAT.md` (live wire is `@halcode/*` + 4-byte length + JSON)
- `docs/open_router.md`, `docs/memory-plan.md`

**Strip:** README bullets and architecture sections that treat pgmem/relmem as core features. Optional one-liner later: “memory plugins sold separately” — not required for this pass.

**Merge then drop:** `docs/qol-roadmap.md` leftovers into issues or architecture (drop pgmem-specific items).

**Move:** `test_ipc.py` → `tests/`.

Strip `/mnt/c/Users/Sean/...` from remaining skills and `cc_find_ipc` examples.

README truth: tools from `cc_tools.json` (JS not listed until ready), abstract sockets, MIT, Python only for `scripts/fetch_providers.py`, MCP is `./HalCode9000.x --mcp`. Clone URL is GitHub.

---

## Phase 4 — Packager (one commit)

- Delete nested `Packager/Packager/`
- Keep `cc_tools/cc_packager_ipc.ailang` + skill
- JS: leave out of `cc_tools.json`; keep building it

---

## Suggested commit order

0. Phase 0 remote retarget (no commit)
1. Phase 1 junk
2. MIT license file + header flip
3. `build.sh` + `setup.sh`
4. Doc cull + architecture rewrite (pgmem/relmem docs gone)
5. Packager delete

Do not reset local `main`.

Working tree is dirty with HalCode source, rebuilt `.x`, Packager, and
untracked `docs/gui-mdi-design.md` + this file. Phase 1 is junk only.
