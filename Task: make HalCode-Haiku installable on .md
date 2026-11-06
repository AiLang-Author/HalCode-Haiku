# Task: make HalCode-Haiku installable on stock Haiku

## Progress

- [x] 1. Platform selection without hand edits
- [x] 2. A compiler on Haiku
- [x] 3. Fix what Hal found
- [x] 4. Ship only what works natively
- [x] 5. `install.sh` on Haiku
- [x] 6. Package it
- [x] 7. Test it the way a tester would

## Goal

- A tester on Haiku R1/beta6 x86_64 installs HalCode from a link with
  one script.
- They get a native HalCode: no Linux machine, no `sys_compat` bridge,
  no `sys_compat` driver.

## Read first

- `HalCode-Haiku/docs/haiku-native-plan.md`:
  - section 9 (rules and traps);
  - sections 10.9-10.12 (what has already been verified).
- `HalCode-Haiku/install.sh` and `build.sh` as they are now.

## Current state

- **Native build works.** HalCode builds with `ailang --haiku` and
  passed the phase 4 gate on the guest: a native `--agent` turn with a
  real provider and a Read tool call.
- **It was cross-compiled.** The Linux host built that binary with a
  compiler built from the uncommitted `haiku` branch of
  `Ailang-Self-Hosting-`.
- **The guest's native compilers are stale.**
  `/boot/home/ailang/ailang_haiku*` predate most of HaikuRT and cannot
  build current HalCode.
- **The platform is chosen by hand edits.** The `Platform/*.ailang`
  selector files (Proc, IPC, HTTP, Fan, Agent, Signal) each import
  either the `*Linux` or the `*Haiku` module.
- **The desk and window are not native (phase 5).** They still run the
  Linux desk through the bridge. Killing a bridged Linux process that
  is blocked in `read()` panics the Haiku kernel (repro in
  `Haiku-Linux-bridge/tests/kill_blocked_read`). Testers must not get
  this path.

### Hal's self-test on the guest (2026-11-05)

- **Passed:** Status, Skills, LS, Bash, Read, Write, Head, Find, Grep,
  Wc, Stat, Du, Diff, Pgmem (including park/pickup), Git, AilangLSP.
- **Relmem:** works, but indexed 0 symbols because `universal-ctags`
  is not installed.
- **Ailang tool:** fails with `Failed to open Linux ELF binary`. The
  `cc_ailang_ipc` wrapper points at a Linux compiler path.
- **`analyzer.x`:** prints its usage message and exits 1 on valid
  input.
- **Every native binary** prints
  `runtime_loader: Failed to get gcc version` on stderr. This is
  harmless.
- **Caveat:** Hal ran inside the desk app, which uses the bridge. Some
  of these results may come from the Linux tool binaries rather than
  the native ones. Re-check each tool you ship with the native build.

## Do

### 1. Platform selection without hand edits

- On Haiku (`uname -s` is `Haiku`), the build uses the `*Haiku`
  platform modules. On Linux it uses the `*Linux` modules.
- Leave no tracked selector file edited after a build. Generate the
  selection into a build directory or an include path, or use another
  mechanism.
- The Linux build must stay byte-identical. Build on Linux before and
  after the change and compare the bytes.

Done on 2026-11-05. `scripts/stage_platform.sh` writes the six
selectors into a directory under `/tmp`. `scripts/compile_halcode.sh`
compiles with that directory as the working directory, because imports
are resolved from there. The tracked `Platform/*.ailang` files stay on
the Linux imports. A Haiku stage imports `ProcHaiku`, `IPCHaiku`,
`SignalHaiku`, `HTTPHaiku`, `FanHaiku`, and `AgentHaiku`. The agent
compile points `UI.ailang` at the shared TUI and leaves this tree's
headless stand-in in place.

The Linux build before the scripts and the Linux build through the
stage are the same file. Both are `/tmp/c_new -march=sse2`, 964320
bytes, sha256
`4b07cb08174107a200137daec3a93cf26a22c68f71524d98702eba03c40b1685`.
That is also `/tmp/HalCode9000_p4.x`. The Haiku stage wrote
`/tmp/HalCode9000_p1_haiku.x`, 1066930 bytes, entry `0x100000b0`,
sha256
`31f48ca2dbd21f1671e096425c14b8f45290dbbb84c7a4f73475503278c258da`,
the same bytes as the phase 4 image. After both compiles the tracked
selectors were still `*Linux`, `UI.ailang` was still the headless
stand-in, and `Applications/` was not left behind.

### 2. A compiler on Haiku

- Testers will not have one. Pick one option and say why:
  - **(a)** Ship prebuilt native binaries: HalCode9000, the ported
    `cc_*_ipc` workers, and optionally the native compiler.
    `install.sh` installs them and only builds when `--build` is given.
  - **(b)** Ship a prebuilt native compiler and build everything on the
    tester's machine.
- Either way:
  - rebuild the native compiler from the current tree first;
  - confirm on the guest that it rebuilds itself to a byte-identical
    fixed point;
  - ship that compiler, so the Ailang tool has something native to
    call.

Done on 2026-11-05. Choice is **(a)**. A tester should get a running
HalCode from one script, not a source build of the compiler and every
tool. The native compiler is still part of that install, because the
Ailang tool has to call one. `install.sh` will copy the prebuilt
binaries and compile only when `--build` is passed. That install
script is phase 5.

`/tmp/c_new -march=sse2 --haiku` compiled the current
`ailang_cli.ailang` to `/tmp/haiku_cc_p2_cross`. The same sources were
copied to `/boot/home/p2cc` (no binaries, no key files). On the guest
that compiler rebuilt itself with `-march=sse2 --haiku` into
`haiku_cc_p2_g2`, and `g2` rebuilt it into `haiku_cc_p2_g3`. All three
are 7915357 bytes, sha256
`1d56f038c1a3a7151f42c21e218d5be059290fd58021f24c3e1bd7f0abbb7235`.
That is the same fixed point as section 10.4, and it still matches
this tree. The copy to ship is `/boot/home/p2cc/ailang_haiku`.
`./ailang.x`, `/tmp/c_new`, `/boot/home/ailang.x`, and
`/boot/home/ailang/ailang_haiku` were not replaced.

### 3. Fix what Hal found

- **Ailang tool:** it is out of sync with the tree in three ways.
  - **Stale binary.** `cc_ailang_ipc` looks up `ailang.x` (PATH, then
    `/usr/local/bin`, `$HOME`, `$AILANG_ROOT`). On the guest that finds
    `/boot/home/ailang.x`: a 2.9 MB Linux build from 2026-08-31 that
    predates `--haiku` and HaikuRT. The tree compiler is about 7.6 MB.
    `/boot/home/ailang/ailang_haiku` (2026-11-05 02:34) is native but
    also stale.
    - The tree's `Librarys/` only updates the libraries a compiled
      program imports. Code generation is compiled into the compiler
      binary, so an old binary keeps old code generation.
  - **No Haiku target.** The tool runs `compiler source output` and
    never passes `--haiku`. On Haiku it must pass `--haiku`, so the
    programs it builds are native and not bridged Linux ELFs. Select
    this through the Haiku platform build, not a runtime branch.
  - **Not ported.** It still starts the compiler with `fork`/`execve`
    and listens on a Unix socket. Port it to `PlatformProc` and the
    port dispatcher, like Read.
  - Fixes:
    - On Haiku, look up the installed native compiler, under a name
      that cannot match a stale Linux `ailang.x` first. Do the same for
      `analyzer.x`.
    - Ship the freshly rebuilt native compiler (step 2).
    - Add a sync check: if the compiler has a build id or version
      option, the installer and the tool compare it with the tree
      they were built from and warn on a mismatch. If it has none,
      propose one in the report instead of adding it.
    - Keep Linux behavior unchanged.
  - Verify natively:
    - one compile whose output is a native Haiku binary (entry
      `0x100000b0`) that runs without `sys_compat_run`;
    - one analyze call.
- **Relmem:** make `install.sh` install `universal-ctags` with
  `pkgman` (it may already try; confirm it works). Without ctags, say
  so in the install output and in `README-HAIKU.md`, rather than
  silently indexing 0 symbols.
- **`analyzer.x`:** find out whether this is a native-build regression
  or present on Linux too. Fix it if the fix is small. Otherwise leave
  it out of the tarball and list it as known.
- **gcc version warning:** document it in `README-HAIKU.md` as harmless.
  Don't patch `runtime_loader`.

Done on 2026-11-05. The Ailang tool now goes through `Platform/AilangRun`.
`scripts/stage_platform.sh` generates that selector with the other six.
The tracked selector imports `AilangRunLinux`. A Haiku stage imports
`AilangRunHaiku`. Linux still looks up `ailang.x` and `analyzer.x`,
forks, and `execve`s with a null envp so the child inherits the
environment. `SpawnStdio` is not used on Linux, because a null envp
there is an empty environment. Haiku looks up
`$HOME/config/non-packaged/bin/ailang_haiku` when that file exists,
otherwise `ailang_haiku` on `PATH`, and the same for `analyzer_haiku`.
It never searches `ailang.x`. The Haiku compile argv is `binary`,
`--haiku`, source, output. The child is `PlatformProc_SpawnStdio`.
Both sides speak `Platform.IPC`.

Linux check, from a linux stage, `/tmp/c_new -march=sse2`: the tool
resolved `/usr/local/bin/ailang.x` and `/usr/local/bin/analyzer.x`. One
compile wrote `/tmp/p3alg/tiny_linux.x`, entry `0x4000b0`, which printed
`P3TOK`. One analyze returned ok with `Summary: 0 errors`. The Linux
binary's strings have `ailang.x` and do not have `--haiku`.

Guest check, from a haiku stage, `/tmp/c_new -march=sse2 --haiku`. The
tool at `/boot/home/p3alg/cc_ailang_ipc_haiku` (222909 bytes, entry
`0x100000b0`) printed compiler `/boot/home/p2cc/ailang_haiku` and
analyzer `/boot/home/p3alg/analyzer_haiku`. `PATH` put `/boot/home/p2cc`
first. `~/config/non-packaged/bin` did not have those names yet, so the
PATH branch ran; that directory is the phase 5 install location, and
Librarys has to sit beside the compiler path. One compile wrote
`/boot/home/p3alg/tiny_haiku.x`, entry `0x100000b0`. Run directly, it
printed `P3TOK` and exited 0. No `sys_compat_run`. One analyze through
the tool returned ok with `Summary: 0 errors`. Afterward `pidof` was
empty for the tool, the client, the analyzer, and `ailang_haiku`.
`listport` was 327 lines and had none of the tool names. Serial is the
`PR59z` banner, 7 bytes, no panic.

`ailang_haiku -v` prints `AILANG 1.0.0`. That is `FixedPool.AilVer`, not
a build id, so a stale compiler prints the same line. No build id was
added. The proposed check is in `README-HAIKU.md`: a stamp file beside
`ailang_haiku` with the sha256 of that binary, and a warning from the
tool when the stamp is missing or does not match.

`analyzer.x` on Linux (`/home/bob/Ailang-Self-Hosting-/analyzer.x`,
428362 bytes) exits 0 on `/tmp/p3alg/tiny.ailang` and prints
`Summary: 0 errors`. The guest file `/boot/home/analyzer.x` is the same
size and its ELF entry is `0x4000b0`, so it is that Linux binary. It
was not executed. A fresh `--haiku` analyzer, 602643 bytes, entry
`0x100000b0`, analyzed the same file on the guest with exit 0 and
`Summary: 0 errors`. The usage-and-exit-1 result was the stale Linux
binary, not a native regression and not a Linux bug. The Haiku tool
calls `analyzer_haiku`. No analyzer source change.

`pkgman install -y ctags` on the guest installed `ctags-6.1.0-2`
(Universal Ctags 6.1.0) at `/boot/system/bin/ctags`. `install.sh` still
does that on Haiku, and a missing `pkgman` or a failed install now
prints `WARNING: universal-ctags is not installed. Relmem will index 0
symbols until ctags is on PATH.` and continues. The same sentence is in
`README-HAIKU.md`. The warning path was not taken on this guest, because
the package installed.

Direct exec of the native client, the native analyzer, and
`tiny_haiku.x` each printed `runtime_loader: Failed to get gcc version`
on stderr and then ran. `README-HAIKU.md` records that as harmless.
`runtime_loader` was not patched.

### 4. Ship only what works natively

- Run each mode on the guest with the native build: `--agent`, `--mcp`,
  and the interactive terminal mode in Haiku's Terminal.
- Include only the tools that pass natively. List each tool's
  `cc_tools.json` entry.
- Leave out the desk, the window and everything that needs
  `sys_compat_run`.
- If no interactive mode works natively yet, say so plainly. Don't ship
  a broken one.

Done on 2026-11-05. The native image is
`/boot/home/p4gate/HalCode9000_p4`, 1066930 bytes, sha256
`31f48ca2dbd21f1671e096425c14b8f45290dbbb84c7a4f73475503278c258da`.
That is the section 10.12 image. `--agent` was not run again. Section
10.12 already recorded one `deepseek:deepseek-flash` turn, one Read,
HTTP 200, and reply `P4_GATE_OK_7f3c`.

`--mcp` was run on that image from `/boot/home/p4ship`. The workers are
the section 10.10 and 10.11 binaries, plus
`/boot/home/p3alg/cc_ailang_ipc_haiku` as `./cc_ailang_ipc.x`. The
directory has no `HalCode9000.x`, so the Agent tool cannot start a
nested provider turn. `tools/list` returned 24 names.
`GOOD 23 BAD 0` and `MCP_EXIT 0`: tools/list plus one call each of
Read, Head, LS, Stat, Wc, Grep, Find, Diff, Du, Undo, Bash, Git,
Skills, Olympus, WebFetch, Packager, Vision, Agent, MCP, Pgmem,
Relmem, and Ailang. The Agent call returned
`Worker spawned asynchronously` and did not start a provider turn. Ailang analyze of
`/boot/home/p3alg/tiny.ailang` contained `Summary: 0 errors`. Pgmem
pickup and Relmem status were database answers; the text
`postgres unavailable` was absent. Park, search, and index were not
called. Write and Edit were not called, so undo `HEAD` stayed `17`.
Their schemas were in `tools/list`, and section 10.10 already recorded
a native write and a native edit on these same worker binaries.

The Linux `cc_tools.json` was not edited. It still lists Sleep and
AilangLSP. Those two, and JS, stay out. Sleep and AilangLSP still
bind a Unix socket. The desk, the window, and `sys_compat_run` stay
out. The ship list is:

- `{"binary": "./cc_read_ipc.x", "name": "Read", "socket": "@halcode/Read"}`
- `{"binary": "./cc_head_ipc.x", "name": "Head", "socket": "@halcode/Head"}`
- `{"binary": "./cc_ls_ipc.x", "name": "LS", "socket": "@halcode/LS"}`
- `{"binary": "./cc_write_ipc.x", "name": "Write", "socket": "@halcode/Write"}`
- `{"binary": "./cc_bash_ipc.x", "name": "Bash", "socket": "@halcode/Bash"}`
- `{"binary": "./cc_webfetch_ipc.x", "name": "WebFetch", "socket": "@halcode/WebFetch"}`
- `{"binary": "./cc_relmem_ipc.x", "name": "Relmem", "socket": "@halcode/Relmem"}`
- `{"binary": "./cc_pgmem_ipc.x", "name": "Pgmem", "socket": "@halcode/Pgmem"}`
- `{"binary": "./cc_agent_ipc.x", "name": "Agent", "socket": "@halcode/Agent"}`
- `{"binary": "./cc_edit_ipc.x", "name": "Edit", "socket": "@halcode/Edit"}`
- `{"binary": "./cc_undo_ipc.x", "name": "Undo", "socket": "@halcode/Undo"}`
- `{"binary": "./cc_find_ipc.x", "name": "Find", "socket": "@halcode/Find"}`
- `{"binary": "./cc_grep_ipc.x", "name": "Grep", "socket": "@halcode/Grep"}`
- `{"binary": "./cc_git_ipc.x", "name": "Git", "socket": "@halcode/Git"}`
- `{"binary": "./cc_stat_ipc.x", "name": "Stat", "socket": "@halcode/Stat"}`
- `{"binary": "./cc_wc_ipc.x", "name": "Wc", "socket": "@halcode/Wc"}`
- `{"binary": "./cc_du_ipc.x", "name": "Du", "socket": "@halcode/Du"}`
- `{"binary": "./cc_diff_ipc.x", "name": "Diff", "socket": "@halcode/Diff"}`
- `{"binary": "./cc_olympus_ipc.x", "name": "Olympus", "socket": "@halcode/Olympus"}`
- `{"binary": "./cc_mcp_ipc.x", "name": "MCP", "socket": "@halcode/MCP"}`
- `{"binary": "./cc_skills_ipc.x", "name": "Skills", "socket": "@halcode/Skills"}`
- `{"binary": "./cc_ailang_ipc.x", "name": "Ailang", "socket": "@halcode/Ailang"}`
- `{"binary": "./cc_packager_ipc.x", "name": "Packager", "socket": "@halcode/Packager"}`
- `{"binary": "./cc_vision_ipc.x", "name": "Vision", "socket": "@halcode/Vision"}`

Interactive mode is not shipped. On a pty, with `CC_NO_SPLASH=1` and a
Read-only manifest, `0` at STEP 1 printed the cooked auth menu and
exited 0. A second run reached STEP 4, created a session, and then
the chat loop did not exit. It sent one `deepseek-v4-pro` completion
(HTTP 200, no tool call) and was still running at 50 seconds, so it
was `kill -9`. Linux ioctl 16 stays untranslated in HaikuRT, so
`TUI_EnableRawMode` cannot set the terminal. The raw chat screen is
not a working Haiku terminal mode.

After the runs, `pidof` was empty for the native HalCode image, curl,
the analyzer, and the Ailang worker. One native Read worker from the
chat run was `kill -9`. `listport` showed empty port tables. The
`halcode` strings in that listing are command lines of bridged teams
that were already running; those teams were left alone. Undo `HEAD`
stayed `17`. The serial log stayed 7 bytes. No commit was made.
Phase 5 was not started.

### 5. `install.sh` on Haiku

- Checks for the OS, x86_64 and curl.
- Installs into a user directory such as `~/config/non-packaged`.
  Don't hard-code `/boot/home`.
- Puts a `halcode` launcher on PATH.
- Asks for provider keys, or skips them with `--skip-keys`. Writes keys
  to `~/.halcode` with mode 600.
- Is safe to run twice.
- Prints what was installed and how to start it.
- Keeps the existing Linux behavior unchanged.

Done on 2026-11-05. On Haiku, `install.sh` checks `uname -s`, `uname -m`
(`x86_64`), and `curl`. It copies prebuilt binaries from
`prebuilt/haiku-x86_64/` into `$HOME/config/non-packaged`. The script
does not contain `/boot/home`. `--build` is the only path that
compiles, and it needs this source tree. The default path does not
compile. The desk, the window, and `sys_compat_run` are not installed.
`cc_tools.haiku.json` is copied to the install as `cc_tools.json`.
The Linux `cc_tools.json` is unchanged.

The compiler is a regular file at
`$HOME/config/non-packaged/bin/ailang_haiku`, with `Librarys/` beside
it and `ailang_haiku.sha256` beside that. The analyzer is
`analyzer_haiku` in the same directory. The agent and the 24 workers
are in `$HOME/config/non-packaged/lib/halcode/`, including
`HalCode9000.x`, which is the name the Agent tool launches. The
`halcode` launcher is in `bin/`. With no arguments it prints how to
start `--mcp` and `--agent` and exits. It does not open the terminal
UI. If `bin/` is not already on `PATH`, one line is added to
`$HOME/config/settings/profile`:
`export PATH="$HOME/config/non-packaged/bin:$PATH"`.

The guest test used `HOME=/boot/home/p5home` and
`/boot/home/p5pkg`. The first run and the second run both finished.
The profile line was written once. `HalCode9000.x` is 1066930 bytes,
sha256
`31f48ca2dbd21f1671e096425c14b8f45290dbbb84c7a4f73475503278c258da`.
`ailang_haiku` is 7915357 bytes, sha256
`1d56f038c1a3a7151f42c21e218d5be059290fd58021f24c3e1bd7f0abbb7235`,
and the stamp matches. `analyzer_haiku` is 602643 bytes. `Librarys/`
is 616 files, the same count as `/boot/home/p2cc/Librarys`. All 24
shipped workers are present. Sleep, AilangLSP, JS, the desk, and
`sys_compat_run` are not. `~/.halcode` in that home is mode 700.
`--build` on that package exited 1 with the missing-source message
and did not run the compiler.

A test key was written to `anthropic_key` with mode 600. The install
log did not contain the key, and the file was removed. The real
`/boot/home/.halcode` key files were not modified. `halcode` with no
arguments exited 0 and printed the start lines. `halcode --mcp` with
empty stdin exited 0. After that, `pidof` was empty for
`HalCode9000.x`, `halcode`, `ailang_haiku`, `analyzer_haiku`, and
`cc_read_ipc.x`. Undo `HEAD` stayed `17`. The serial log stayed 7
bytes. `/boot/home/config/non-packaged/bin/halcode` was not created.

On Linux, `install.sh --help` still prints the original usage, and
`install.sh --build` exits before any compile with `--build is for
Haiku`. `bash -n` passed. No commit was made. Phase 6 was not started.

### 6. Package it

- Produce a release tarball, for example
  `halcode-haiku-<version>-x86_64.tar.gz`, containing:
  - `install.sh`;
  - the binaries or the sources;
  - `cc_tools.json`;
  - a short `README-HAIKU.md`: requirements, install, run, what works,
    what doesn't, known issues, how to send feedback.
- Add a SHA-256 checksum file.

Done on 2026-11-05. The host had been hard-rebooted, so the guest was
booted once from the existing disk. `qemu-img check` reported no
errors before that boot. The release files are in `/home/bob/HalCode-Haiku/dist/`. The first
tarball was 5548777 bytes, sha256
`50f2cca02e0f90a9622207e51d279d0a4c89a01f85efe380062903de494ca3ce`.
Phase 7 found that the launcher did not `cd` to the tool directory,
so `--agent` never opened `cc_tools.json`. The launcher now does that
`cd` before `exec`. The archives were rebuilt from the same prebuilts.
The prompt fix rebuilt them again.
`halcode-haiku-1.0.0-x86_64.tar.gz` is 5706880 bytes, sha256
`f5c5f1671c241c28e924bd0df2d1c39b01ab0c5ab4d35861c7943f341edbc3b3`.
`halcode-haiku-1.0.0-x86_64.zip` is 6096874 bytes, sha256
`296aab6fbc39e362cb8e20a3e836e50b95946f33b9d961f96df946f0d23972ec`.
Both `sha256sum -c` checks passed. The host key files are not in
either archive. Copies are on the guest at `/boot/home/`. `dist/`
is listed in `.gitignore`, and so is `*.zip`. Nothing was committed
or uploaded.

The archive has one top directory, `halcode-haiku-1.0.0-x86_64/`.
It contains `install.sh`, `README-HAIKU.md`, `cc_tools.json`,
`cc_tools.haiku.json`, `config/system_prompt.txt`,
`scripts/haiku_postgres.sh`, `scripts/haiku_runas.c`, and
`prebuilt/haiku-x86_64/`. The `1.0.0` in the name is the
`AILANG 1.0.0` string from `ailang_haiku -v`. Both tool lists are the
24 Haiku tools. The repo `cc_tools.json` is still the Linux list,
including Sleep and AilangLSP.

The prebuilts match the phase 5 measurements. `HalCode9000.x` is
1066930 bytes, sha256
`31f48ca2dbd21f1671e096425c14b8f45290dbbb84c7a4f73475503278c258da`.
`ailang_haiku` is 7915357 bytes, sha256
`1d56f038c1a3a7151f42c21e218d5be059290fd58021f24c3e1bd7f0abbb7235`.
`analyzer_haiku` is 602643 bytes. `Librarys/` is 615 regular files.
The build tree also had a dangling symlink `Librarys/Ecu` pointing at
`/home/bob/ECU/Librarys/Ecu`. That link is not in the tarball. All 24
workers are present. Sleep, AilangLSP, JS, the desk, and `sys_compat`
are absent. `install.sh` in the archive does not contain `/boot/home`.

The secret scan read every archive member. The three guest key files,
lengths 35, 108, and 84, do not occur. The three host key files, the
same lengths, do not occur. No member name is a key file, a log, or a
banned binary. `HalCode9000.x` contains the identifier `api_key` three
times. One 12-byte `sk-` match is the tail of the comment word
`disk-fw-header` in `Library.AMDGPUDPM_SI.ailang`.

This phase did not run `install.sh`, `--agent`, or `--mcp`.
`/boot/home/config/non-packaged/bin/halcode` is absent. Undo `HEAD`
read `21`. Phase 5 recorded `17`. This phase did not write that file.
The serial file is 0 bytes and has no PANIC. Tracked selectors are
still `*Linux`. `UI.ailang` is still the headless stand-in. No commit
was made. Phase 7 was not started.

### 7. Test it the way a tester would

- On the guest, use a fresh user directory with no earlier HalCode
  files on PATH.
- Unpack the tarball and run `install.sh`.
- Run one cheap `--agent` turn that makes a Read call: the cheapest
  model and a short prompt. It spends real provider credits, so run it
  once.
- Run one native Ailang tool call (step 3).
- Afterwards, check that no curl, HalCode or worker process and no
  HalCode ports are left over.

Done on 2026-11-05. Fresh home was `/boot/home/p7home`. The tarball
was unpacked and `./install.sh --skip-keys --skip-postgres` exited 0.
The real prefix `/boot/home/config/non-packaged/bin/halcode` was not
created. The profile line is `export PATH="$HOME/config/non-packaged/bin:$PATH"`
with one marker and no hard-coded `/boot/home`.

The first `--agent deepseek:deepseek-flash` run was started from
another directory. The launcher had not `cd`'d to the tool directory,
`cc_tools.json` was not opened, and the model reported that only
Status was registered. That call returned HTTP 200 and did not Read.
The launcher was changed to `cd` first, and the tar.gz and zip were
rebuilt. A second run of the same command replied `P7_READ_OK_9c2e`,
the exact contents of the file it was asked to Read. The debug log
was removed after the status lines were counted. It recorded several
`Request OK` lines with `HTTP status=-1` (the Haiku status capture
did not fill a code). The reply still matched the file.

One `--mcp` session called the Ailang tool. Compile wrote
`/boot/home/p7home/p7_tiny.x`, entry `0x100000b0`, 32862 bytes. Run
directly, it printed `P3TOK` and exited 0. Analyze returned a report
for the same source. No `sys_compat_run` was used.

Afterwards `pidof` was empty for HalCode, the compiler, the analyzer,
and the Read and Ailang workers. One native `cc_pgmem_ipc.x` (pid
2082) was still listening and was `kill`ed. The bridged
`sys_compat_run` teams were left alone. Their port tables were empty.
A curl pid appeared and exited before its command line could be read.
Undo `HEAD` read `22`. It was `21` at the start of this phase. This
phase did not call Undo. The serial file is 7 bytes and has no PANIC.
`Ailang-Self-Hosting-/ailang.x` is still 6954176 bytes, sha256
`67e25f5b47f77bb461f7b7aad5f719aaa2ea7ddc403a569fe9d3a7962cf65c37`.
No commit was made.

## Hard rules

- **No secrets in the tarball.** Never include API keys, key files,
  `~/.halcode` contents, logs or `/tmp` debug files. Scan the finished
  tarball for key patterns and for the guest's actual key strings
  (without printing them), and report that it is clean.
- Don't replace `Ailang-Self-Hosting-/ailang.x`.
- **Nothing outward-facing.** Don't commit, push, create tags or
  releases, or upload anything. The owner reviews and publishes.
- The `--haiku` compiler work is uncommitted on the `haiku` branch.
  List exactly which files in both repos must be committed for someone
  else to rebuild from source.
- Don't use or run the bridge path on the guest, except to confirm it
  was left out. Don't run HalCode in the desk app for these tests.
- Leave the unrelated CAD and DAW files alone.

## Report at the end

- What changed, and why option (a) or (b).
- The tarball path, its size and its SHA-256.
- The tester-style install on the guest: the agent turn, the Ailang
  tool call, and the leftover process and port check.
- The tarball secret scan result.
- The Linux before/after byte comparison.
- Which modes and tools work natively, and which were left out and why.
- The fixes for Hal's findings: Ailang wrapper, Relmem/ctags,
  `analyzer.x`.
- The list of files to commit before publishing.
