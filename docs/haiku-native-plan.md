# Plan: native HalCode on Haiku

Status: phases 1, 2, 3, and 4 complete on 2026-11-05. Groups 1–3 are section 10.10. Group 4, including a real Pgmem pickup and Relmem status, is section 10.11. The phase 4 agent turn is section 10.12.
Branches: `haiku` in `Ailang-Self-Hosting-` (compiler and runtime) and
`HalCode-Haiku` (application). Nothing is committed yet.
Measurements are in section 10. No section of this plan has been removed.

Read section 9 before starting. It lists the rules and the traps that
have already cost time on this port; most of them fail silently.

## 1. Goal

Build HalCode with `ailang --haiku`, so every binary calls the Haiku
kernel directly and nothing goes through the Linux bridge. The agent,
the JSON protocol, the providers and the UI code stay shared with
HalCode9000. Only the platform layer differs.

## 2. Why

Linux HalCode under the bridge panics the Haiku kernel. MCP mode starts
each tool worker, fetches its schema, then kills it. Killing a Linux
process that is blocked in `read()` takes the bridge's doom-kill path,
and Haiku's `handle_signals` faults.

| Item | Value |
|---|---|
| Panic | General Protection Exception in kernel mode, `handle_signals + 0x1d9` |
| Call chain | `x86_return_to_userland` → `thread_at_kernel_exit` → `handle_signals` |
| User frame | All registers 0, `rflags 0x202`, `vector 0x63`, RIP just past the `read` syscall |
| Bridge code | `sys_compat_kill` → `doom_add` + `send_signal_etc(target, 9)`; the doom return path builds that frame by hand and jumps to `x86_return_to_userland` (`src/sys_compat_dev.cpp`, about line 7946) |
| Repro | `Haiku-Linux-bridge/tests/kill_blocked_read/`: `victim.c` blocks in `read(0)`, `killer.c` calls `kill(pid, 15)`. Both are run through `sys_compat_run`. Panics every time. |
| Control | A native Haiku `kill -TERM` against the same victim does not panic. It also does not kill the victim: the signal is ignored while it waits in the bridged read. |
| Not the cause | The new compiler. All 26 HalCode binaries are byte-identical to the HEAD compiler's output. |

The bridge fix is a separate track (section 7). A native build avoids
the bridge entirely, which is the right long-term answer for HalCode.

## 3. What HalCode needs from the OS

Linux syscalls found in the HalCode binaries that `HaikuRT` does not
yet handle. This comes from a scan for `mov $N,%rax; syscall`, so
calls made through a pool constant are missing from it; phase 1 starts
with a full list.

| Area | Linux calls | Used for |
|---|---|---|
| Tool IPC | socket, bind, listen, accept, connect, setsockopt | `SOCK_SEQPACKET` at `/tmp/ailang_cctools/<Tool>.sock` (see `SEQPACKET_WIRE_FORMAT.md`) |
| Processes | fork, execve, wait4, kill, setpgid, prctl | Tool workers, `curl`, `bash`, `git` |
| Event loop | poll, fcntl, ioctl, pipe, dup2 | Waiting on workers and `curl` output |
| Signals | rt_sigaction | SIGINT/SIGTERM default or ignore, SIGPIPE ignore |
| Threads | clone (via `ThreadTrampoline`) | Background work in the agent |
| Misc | ftruncate, time, stat family | Files and timestamps |

HTTPS needs no TLS work: HalCode runs `curl` as a child process, and
Haiku ships `curl`.

## 4. IPC choice: kernel ports, not BMessage directly

`BMessage` is the Haiku way to do this, but it is a C++ class in
`libbe`. Underneath, it is a flattened buffer sent over a kernel
**port**. AILang can call ports directly: `create_port` 222,
`find_port` 225, `read_port_etc` 230, `write_port_etc` 232,
`delete_port` 224 (hrev59866 numbers; regenerate per build).

Ports fit HalCode's protocol well:

- **Message boundaries.** One `write_port` is one `read_port`, which is
  the property HalCode chose `SOCK_SEQPACKET` for. The JSON envelope
  stays the same.
- **Named, with no files.** `find_port("hc.Read")` replaces the socket
  path, so there are no `/tmp` files to go stale.
- **Cleanup.** A port is deleted when the team that owns it dies, so a
  killed worker cannot leave a dead endpoint behind.
- **Replies.** Ports are one-way. Each client creates a reply port and
  sends its id in the request, which is how `BMessenger` replies work.

Limits to confirm in phase 1:

- Maximum message size. Believed to be 256 KiB; large tool output then
  needs chunking with a `more` flag.
- Port name length (`B_OS_NAME_LENGTH`, 32).
- Queue capacity, set per port at `create_port`.

The payload is the existing JSON, not a flattened `BMessage`. A later
step can send real `BMessage`s to the C++ window
(`halcode_shell_haiku`), which would let it drop the frame and command
files.

Fallback: Haiku also has path-based `AF_UNIX` sockets (`socket` 166,
and so on). Whether it supports `SOCK_SEQPACKET` is not checked yet. If
ports run into a blocker, stream sockets with length-prefix framing
also work.

## 5. Where the code splits

There is one platform interface with two implementations. Everything
above it is shared.

```
shared:  agent loop, JSON, History, UI, providers, tool logic
            │
            ▼
Platform.IPC      Listen(name) Accept Connect(name) Send Recv Close
Platform.Proc     Spawn(path, argv, envp, stdio) Wait Kill Exists
Platform.Signal   Ignore(sig) Default(sig)
            │
     ┌──────┴───────┐
  Linux impl     Haiku impl
  SEQPACKET,     ports,
  fork/execve,   load_image/resume_thread,
  kill/wait4     kill_team/wait_for_thread
```

Rules:

- No `SystemCall` outside the platform modules, except plain file I/O
  that `HaikuRT` already translates.
- Each build selects its platform modules: Linux builds import
  `Platform.*.Linux`, Haiku builds import `Platform.*.Haiku`. There are
  no runtime `if haiku` branches in shared code.
- The Linux build must stay byte-identical until a phase deliberately
  changes it. When one does, rerun the HalCode9000 tool tests before
  merging.

## 6. Phases

Each phase finishes only when its gate passes.

### Phase 0: bridge bug filed (done except filing)

- Repro saved in `Haiku-Linux-bridge/tests/kill_blocked_read/`, with
  the panic in `panic.txt`.
- Gate: the issue is written up with the repro. The fix is section 7.
- Status: the writeup is this plan plus that repro. The GitHub issue
  was not opened. The session that measured section 10 was unattended,
  so filing was left for the owner. Section 7 is still not started.

### Phase 1: HaikuRT system layer (compiler repo)

1. Get the full list of HalCode syscalls, including pool-indexed ones,
   by logging them in HaikuRT's `-ENOSYS` path while running each tool.
2. Add raw Haiku wrappers: ports, `load_image`, `resume_thread`,
   `wait_for_thread_etc`, `kill_team`, `send_signal`, `sigaction`,
   `create_pipe`, `dup`/`dup2`, `fcntl`, `poll`, `read_stat`,
   `spawn_thread`.
3. Translate the Linux calls HalCode makes and that can be translated
   directly: `poll`, `fcntl`, `pipe`, `dup2`, `stat`/`fstat`,
   `ftruncate`, `time`, `kill`, `wait4`.
   - `fork` + `execve` cannot be translated in general. The platform
     layer calls `load_image` instead (phase 2).
4. Write one small `--haiku` test program per wrapper. Run them on the
   VM, natively.
- Gate:
  - all wrapper tests pass on the VM;
  - the Linux 928-program byte sweep shows 0 differences from HEAD;
  - the Haiku-hosted compiler still rebuilds itself byte-identically.
- Status: complete. The three gates are recorded in section 10.
  The only HalCode syscall still untranslated on purpose is `mremap`
  (25), used by the JS JIT, not by HalCode's tools.

### Phase 2: platform modules (HalCode-Haiku)

1. Write `Platform.IPC`, `Platform.Proc` and `Platform.Signal`, with
   Linux implementations that wrap the current code without changing
   its behavior.
2. Move the existing `SystemCall` uses in `IPCDispatch.ailang`,
   `HalCode9000.ailang` and the worker skeleton behind the interface.
3. Write the Haiku implementations: ports and `load_image`.
- Gate:
  - the Linux HalCode binaries are byte-identical to before the move,
    or every difference is explained and the HalCode9000 tool tests
    pass;
  - a two-process port echo test passes natively on the VM.
- Status: complete. The platform modules, the port echo, and the
  process and worker tests are in section 10. `CC_LaunchTool`,
  `IPCDispatch_Respawn`, the Main signal setup, and the `kill` /
  `wait4` sites in `HalCode9000.ailang` and `IPCDispatch.ailang` call
  the platform. File I/O and `poll` stay direct `SystemCall`s, which
  section 5 allows where `HaikuRT` already translates them.
  Two shell `fork` / `exec` sites stay on purpose. `CC_SessionInit`
  runs `find` and `du` through `/bin/sh -c`, and `CC_RunModelScraper`
  runs `scripts/fetch_providers.py` the same way. `SpawnWorker` sends
  the child's stdout and stderr to `/dev/null` and cannot pass a
  pipe, so those two still need the raw fork. On Haiku that fork
  returns `ENOSYS`; they are not tool workers.
  The Linux HalCode image is not byte-identical to the pre-move
  binary: the move replaced inline spawn, signal, kill, and wait
  sequences with calls into `Platform`. The safe tool checks passed
  (section 10.7). Host `HalCode9000 --mcp` was not run; it calls
  `CC_KillStaleTools` and would signal unrelated workers. The guest
  `--mcp` run is section 10.10.
  Haiku `load_image` has no `prctl` parent-death and no `dup2`.
  Shutdown has to kill the team. The checked-in selectors
  `Platform/Proc.ailang` and `Platform/IPC.ailang` import the Linux
  modules. A Haiku image is built by pointing those two lines at the
  Haiku modules for that compile, then restoring them.

### Phase 3: first native tools

Port in order of risk, lowest first:

1. Read, LS, Stat, Wc, Head: files only.
2. Grep, Find, Diff, Du, Edit, Write, Undo.
3. Bash and Git: spawn `/bin/sh` or `git` with pipes.
4. Agent, MCP, Skills, Olympus, Packager, pgmem, relmem, Vision,
   WebFetch: the rest.

- Gate per tool: the tool answers the schema request and one real call
  through `HalCode9000 --mcp` on the VM, and can be killed and
  restarted 50 times with no leaked ports or teams. Check with
  `listport` and `ps`.
- Status: complete. Groups 1–3 passed the guest gate in section
  10.10. Group 4 listens through `PlatformIPC`. Every tool in the
  list above answered schema and one real call on the guest, and each
  was killed and restarted 50 times with `listport` clear (section
  10.11). `ps` was not used. Pgmem pickup returned the seeded content
  `PGMEM_OK`. Relmem status returned the live count
  `0 files, 0 symbols, 0 edges`. Park, search, index, and the other
  Pgmem and Relmem operations still answer `postgres unavailable` on
  this path. `socket` stays `ENOSYS`. The query runs guest `psql`
  through `load_image` of `/bin/sh`.

### Phase 4: native agent

1. `HalCode9000 --haiku` in MCP mode: boot schemas, `tools/list`,
   `tools/call`.
2. Agent mode: run `curl` for one provider request and stream
   server-sent events through a pipe.
3. Threads: back `ThreadTrampoline` with `spawn_thread`, or remove the
   need for it in the Haiku build.
- Gate: one full agent turn, from prompt through a tool call to the
  answer, runs natively on the VM against a real provider.
- Status: complete. Section 10.12. The guest turn used `deepseek-flash`,
  got HTTP 200, called Read once, and wrote the file token to
  `reply.txt`. `CCFan` is not started in this build. `spawn_thread` is
  still deferred. Section 7, Sleep, Ailang, AilangLSP, JS, and the
  other Pgmem operations were not in the run.

#### Phase 4 decisions (2026-11-05)

These answer the three gaps found before phase 4 started: the curl
launch, agent-mode tool attach, and CCFan. Facts marked "verified" were
tested on the guest (hrev59866, curl 8.21.0).

Verified facts:

- `load_image` keeps the parent's ordinary file descriptors in the
  child at the same numbers, and closes those marked `FD_CLOEXEC`.
- `/dev/fd` does not exist on Haiku, so no argument can name a
  descriptor by path.
- `curl -K -` reads the whole config (url, headers, body) from stdin.
- `-w '%{stderr}...'` sends the status record to stderr.
  `%{http_code}`, `%{exitcode}` and `%{errormsg}` all work.
- A body given as `data-binary = "..."` in the config arrives byte-exact
  (checked against an echo server), including UTF-8, once escaped as
  below.

**1. Provider request: three standard descriptors, no /dev/fd.**

- Start curl with argv `curl -s -N -K - -w '%{stderr}HCSTATUS ...'`
  plus the timeout flags, and nothing secret.
  - fd 0: config pipe. It carries `url`, every `header` (including the
    API key) and `data-binary` (the body). Write it after curl has
    started, then close it, so the 64 KiB limit on writing before the
    spawn no longer applies.
  - fd 1: stream pipe. The parent reads server-sent events from it, as
    today.
  - fd 2: status pipe. The parent reads the `HCSTATUS` line after the
    stream reaches EOF, which replaces the `/dev/fd/4` record.
- Nothing secret goes in argv, in the environment or on disk.
- Escaping rule for quoted config values:
  - `\` becomes `\\`, and `"` becomes `\"`;
  - LF, CR and TAB become `\n`, `\r` and `\t`;
  - all other bytes, including UTF-8, pass through unchanged.
- How to spawn with those descriptors:
  1. Mark every pipe end the parent keeps `FD_CLOEXEC`.
  2. Save fds 0–2 above 10 with `F_DUPFD`, and mark the copies
     `FD_CLOEXEC`.
  3. `dup2` the child's ends onto 0, 1 and 2.
  4. Call `load_image`, then `resume_thread`.
  5. Restore 0–2 from the saved copies, and close the saved copies and
     the child's ends.

  This is the same pattern as `PlatformProc_SpawnWorker`. Generalize
  it as `PlatformProc_SpawnStdio(path, argv, envp, fd0, fd1, fd2)`
  rather than writing a second copy.
- The swap is safe only when no other thread touches fds 0–2 during it.
  Phase 4 is single-threaded (decision 3), and spawns must still happen
  one at a time.
- The shared `HTTP_SpawnCurl` keeps its Linux fork/exec code. The Haiku
  build gets its own spawn and config writer, behind the platform
  layer, with no runtime `if haiku` branch.
- Leak gate: two overlapping requests. The first stream must reach EOF
  when the first curl exits. If it hangs, a write end leaked into the
  second curl.

**2. Tools in agent mode use the port dispatcher.**

- On Haiku, `--agent` attaches tools through the same port dispatcher
  that `--mcp` already uses: start the worker on demand and call it
  over ports.
- Skip `IPCDispatch.ConnectProxy()` and `@halcode/AgentProxy` in the
  Haiku build.
- A shared, port-based tool host is phase 5 work, if the desk needs
  one.

**3. No CCFan threads in the phase 4 Haiku build.**

- Compile `CCFan_Init` and `CCFan_Shutdown` out of the Haiku build. A
  failed init is already harmless, and the join in `CCFan_Shutdown` has
  hung before.
- Decision 1 also depends on this.
- Backing `Thread_Spawn` with `spawn_thread` is deferred. When it
  comes, every writer to fds 0–2 must take the same lock as the spawn
  swap, or log through a descriptor saved at startup.

**Gate run.** Use a cheap model and a short prompt that forces one Read
call. The guest already has the key files, and each run costs provider
credits. Leave out section 7 of this plan, Sleep, Ailang, AilangLSP and
JS, and the Pgmem operations; the gate doesn't need them.

### Phase 5: desk and window

1. Build `halcode_desk` with `--haiku`. It already talks to the window
   through files, so this is mostly the phase 1 to 3 work again.
2. Optional: replace the frame and command files with ports or
   `BMessage`s between the desk and `halcode_shell_haiku`.
- Gate: `launch_halcode.sh` starts the native desk with no
  `sys_compat_run`, and a chat turn works in the window.

### Phase 6: HalBot

Same platform modules. HalBot also needs the network socket path
(`AF_INET`); Haiku's `sockaddr` layout must come from its headers. The
details are planned after phase 4.

## 7. Bridge fix (separate track)

HalCode will not depend on it, but anything else that runs Linux
binaries through the bridge can hit it.

- Find the field at `handle_signals + 0x1d9`: disassemble Haiku's
  kernel for hrev59866. `rdx`/`r15` were -1 in the repro and -65 in
  the HalCode crash, which looks like a bad signal or index value.
- Suspect: the doom path returns to userland through a hand-built
  frame on the kernel stack while a SIGKILL is pending. Haiku then
  handles that signal against thread state the bridge did not set up.
- Two candidate fixes:
  - When the target is blocked in a bridged syscall, end it with
    `sys_compat_exit_team(128 + sig)` in its own context instead of
    returning to userland.
  - Or make the bridged read wait with `B_CAN_INTERRUPT`, so the
    ordinary Haiku SIGKILL path ends it.
- Related: a native SIGTERM to a bridged process blocked in `read()`
  is ignored (see the control in section 2).
- Gate: the repro passes with signal 15 and with signal 9, and the
  bridge regression suite still passes.

## 8. Risks

| Risk | Mitigation |
|---|---|
| Port message size limit | Chunking with a `more` flag; measure the limit in phase 1 |
| `load_image` takes a packed argument block | Build it in HaikuRT once; test with argv and envp containing spaces and long strings |
| Haiku signal numbers differ from Linux | Use Haiku's numbers from its headers in the Haiku platform module only |
| Syscall numbers change between Haiku builds | Regenerate from the guest's `libroot.so` every time Haiku is updated (existing tool) |
| Linux HalCode regresses during the split | Byte comparison gate in phase 2 |
| Shared code drifts between HalCode9000 and HalCode-Haiku | Shared code outside `Platform.*` is synced from HalCode9000, not edited here |

## 9. Rules and traps for implementers

### 9.1 Hard rules

- Do not commit, unless the owner asks. Work stays uncommitted on the
  `haiku` branch of `Ailang-Self-Hosting-` and in `HalCode-Haiku`.
- Never replace or rebuild `Ailang-Self-Hosting-/ailang.x`. It is the
  trusted compiler. Build new compilers to other paths.
- Leave unrelated uncommitted files (the CAD and DAW work) alone.
- Do not kill bridged Linux processes on the VM. Section 2's panic hits
  every time, and the VM then needs a reset. Killing native `--haiku`
  processes is fine.

### 9.2 Haiku syscall numbers

- Haiku numbers its syscalls in the order of `syscalls.h`, so the
  numbers change between Haiku builds. Never type them in from headers,
  docs or memory. Stale hand-typed numbers (26 of 30 wrong) once made
  every native binary crash after its first syscall with no output.
- Regenerate from the guest's own `libroot.so`:
  ```
  scp -P 2222 user@127.0.0.1:/boot/system/lib/libroot.so /some/dir/
  cd Librarys/Compiler/Compile/Modules/syscall_generator_tools
  python3 extract_haiku_syscalls.py /some/dir/libroot.so \
      --ailang ../../../../Haiku/Library.HaikuNr.ailang
  python3 generate_sysdispatch.py
  ```
  This writes `haiku_syscall_numbers.py`, `Librarys/Haiku/Library.HaikuNr.ailang`
  and `Library.CSysDispatch.ailang`. In the runtime, use the names in
  `FixedPool.HaikuNr` (for example `HaikuNr.CREATE_PORT`), not
  literals.
- The numbers in this plan are for hrev59866 and are for reading only.

### 9.3 Haiku ABI

- Syscall arguments go in rdi, rsi, rdx, r10, r8, r9, the same as
  Linux.
- Calls that return `int` or `status_t` are valid only in EAX. Sign-
  extend (`movsxd rax, eax`, or `HaikuRT_R32`) before testing for an
  error. If you skip this, errors look like large positive numbers.
- Errors are `B_*` codes (large negative numbers, for example
  `ENOENT` = -2147459069), not Linux errnos. Convert them with
  `HaikuRT_Errno` wherever Linux-style code reads the result.
- `_kern_read`/`_kern_write(fd, pos, buf, len)` take a position; -1
  means "current position".
- `_kern_open(dirfd, path, flags, mode)`: dirfd -1 means the current
  directory. The open flag bits differ from Linux; `HaikuRT_OpenFlags`
  translates them.
- Signal numbers, `sockaddr` layout (BSD-style, with a length byte)
  and address-family values differ from Linux. Take them from Haiku's
  headers, and only use them in the Haiku platform module.
- `runtime_loader` calls the entry point as `(argc, argv, env)` in
  rdi, rsi, rdx. The syslog line "Failed to get gcc version" is
  harmless.

### 9.4 Load address and the bridge

- The bridge treats any syscall from code at 0x400000-0x700000 as a
  Linux syscall when no Linux team is marked. A native binary loaded
  there has its Haiku syscalls rewritten and breaks.
- `--haiku` links at `ELFDefault.HAIKU_BASE_ADDR` = 0x10000000. Keep
  it there.
- Any C or assembly test program you build for the guest must also
  load outside that range.

### 9.5 AILang compiler facts that matter here

- `FixedPool` members live in a block that R15 points to. R15 is
  created by a startup `mmap`, so pool constants are runtime loads.
  Nothing that runs before the pool setup can read them.
- Function arguments go in rdi, rsi, rdx, rcx, r8, r9 (at most 6).
- `SystemCall` is a lexer keyword. Under `--haiku`, every `SystemCall`
  calls `HaikuSys_Call` in `Librarys/Haiku/Library.HaikuRT.ailang`,
  which translates the Linux call or returns `-ENOSYS`. New Linux
  calls are added there.
- Inside `Library.HaikuRT.ailang` only: no `Allocate`, no
  `SystemCall`, no `Print*`. Those go through the shim and would
  recurse. Use the raw builtins `HaikuSyscall(...)` and
  `HaikuAnonMap(len, prot)`.
- The compiler reads its own arguments and environment from
  `/proc/self/cmdline` and `/proc/self/environ`. HaikuRT fakes those
  two paths, and nothing else in `/proc`.
- Set `AILANG_LIB_PATH=<tree>/Librarys` when the compiler binary is not
  inside the tree, or imports fail with "Cannot read".

### 9.6 Verification

Run these before calling any compiler or runtime change done.

1. Linux byte sweep against HEAD. The baseline must be a compiler built
   from a clean `git archive HEAD` tree by `./ailang.x`. Do not use
   `./ailang.x` itself: it is older than HEAD, so its output differs
   for reasons that have nothing to do with your change.
   ```
   git archive HEAD | tar -x -C /work/base
   cd /work/base && AILANG_LIB_PATH=/work/base/Librarys \
       /home/bob/Ailang-Self-Hosting-/ailang.x ailang_cli.ailang /work/c_base
   # build /work/c_new the same way from a copy of HEAD plus your changes
   tools/haiku/sweep_hash.sh /work/c_base /work/base tools/haiku/entries.txt base.tsv /work/w1
   tools/haiku/sweep_hash.sh /work/c_new  /work/new  tools/haiku/entries.txt new.tsv  /work/w2
   diff <(LC_ALL=C sort base.tsv) <(LC_ALL=C sort new.tsv)
   ```
   - The script compiles all 928 entry programs for Linux and for
     `--haiku`, and writes one line per program: path, exit code, hash.
   - Expected: no differences in the Linux columns, unless the change
     is meant to alter Linux output.
   - Already broken before this work: three programs in
     `dev/compiler-regression` crash the compiler at HEAD
     (`4_integrated_system_test`, `fizzbuzz`, `message_passing_demo`).
2. Self-host on Haiku. Copy the native compiler to the guest, then have
   it rebuild itself twice. Generations 2 and 3 must be byte-identical
   to the Linux cross-build.
3. Sweep on the guest. `/boot/home/sweep/` holds a tree, a native
   compiler (`cc_haiku`) and the same script. Compare its results with
   the host's after `LC_ALL=C sort`, counting exit codes 139 (Linux)
   and 149 (Haiku) as the same crash.

### 9.7 VM access

- Start: `nohup /home/bob/Haiku-Linux-bridge/scripts/run_qemu.sh &`.
  SSH is ready in about 30 s: `ssh -p 2222 user@127.0.0.1` (`scp -P 2222`).
- Guest: Haiku R1~beta6 hrev59866. Bridge loader
  `/boot/home/sys_compat_run`. Compiler tree `/boot/home/ailang/`.
  The current HalCode install, which runs through the bridge, is in
  `/boot/home/HalCode-Haiku`.
- Hung or in `kdebug`: the panic text is in
  `/home/bob/Haiku-Linux-bridge/haiku_serial.log`. Save it, then reset
  through the QEMU monitor socket:
  ```
  python3 -c "import socket,time;s=socket.socket(socket.AF_UNIX);s.connect('/home/bob/Haiku-Linux-bridge/qemu_monitor.sock');s.recv(4096);s.send(b'system_reset\n');time.sleep(1)"
  ```
- In `ps` output, the team id is the fourth field from the end, not
  the second.
- A background job started over SSH keeps the session open. Redirect
  its stdin and stdout, or use `ssh ... </dev/null` with a timeout.
- The root disk on the build machine is nearly full. Delete sweep work
  directories and spare compiler copies when done.
  On 2026-11-05 `/` had about 48G free. The sweep outputs under `/tmp`
  were kept because section 10 cites them.

## 10. Measured results (2026-11-05)

These notes were added when the work was measured. The sections above
are unchanged apart from a status line on each phase.

### 10.1 Phase 1 syscall inventory

`tests/haiku/scan_syscalls.py` over the HalCode import closure:
152 files, 1047 `SystemCall` sites. The only number with no HaikuRT
translation and not an intentional `ENOSYS` is 25 (`mremap`, two
sites in `Library.JSJIT`). `fchmod` (91) is translated.
Intentional `ENOSYS`: ioctl 16, socket 41/42/43/49/50/51/54, accept4
288, clone 56, fork 57, execve 59, prctl 157, futex 202, epoll
232/233/291, signalfd 289. Fork and exec stay `ENOSYS` in the
translator; the platform calls `load_image` instead.
Names the scanner could not fold (`SysNr.MMAP`, `MUNMAP`,
`NANOSLEEP`) are the handled numbers 9, 11, and 35.

### 10.2 Wrapper tests on the guest

`tests/haiku/run_native.sh` on 2026-11-05, log
`/tmp/haiku_native_suite2.log`: `FAILURES 0`. Passed: `t_chdir`,
`t_dents`, `t_fchmod`, `t_fcntl`, `t_hello` (exit 42), `t_killwait`,
`t_load`, `t_pipe_poll`, `t_port`, `t_portecho`, `t_signal`,
`t_spawn`, `t_stat`, `t_time`, `t_trunc`.
Separate platform tests, all exit 0: Linux `t_proc_linux`,
`t_ipc_linux`, `t_worker_linux`; Haiku `t_platform` and
`t_worker_haiku`. The Haiku worker test spawns `/bin/sleep`,
`setpgid`s the team, kills the process group with signal 15, and
sees wait status 15.

Port limit, measured earlier this effort: a 262144-byte write
succeeds and 262145 returns `B_BAD_VALUE`. One write is one read.
`B_OS_NAME_LENGTH` is 32.

### 10.3 Linux byte sweep

Compilers, both built by the stock `./ailang.x` (not overwritten):
`/tmp/c_base` from `git archive HEAD` (7627972 bytes, no `--haiku`
flag; an unknown `--haiku` is ignored and the Linux bytes match a
normal compile), `/tmp/c_new` from the dirty tree (7632489 bytes).
`tests/contract/ok_program.ailang` compiled by both is byte-identical,
sha256 `4aa7bd3333b7f1cafed1f0c1213ab9a9ee26a545a072c3d62903fd80aa8429e7`.

The 928-program sweep of the dirty tree against the archive differed
in 121 Linux results. Recompiling those 121 with `/tmp/c_new` against
the archive tree matched `/tmp/c_base` on every one (`SAME 121 DIFF 0`,
`/tmp/same_tree.tsv`). The other 807 already matched, including the
three programs that crash both compilers with exit 139
(`4_integrated_system_test`, `fizzbuzz`, `message_passing_demo`).
The 121 were not a codegen change:

- 117 programs import `Cad.CAD_Topo`, which imports the uncommitted
  Fillet libraries.
- `LLM.ailang` and `dev/compiler-regression/test_hal_gcn.ailang` need
  `Librarys/TF/`, which is gitignored, so `git archive` does not
  contain `TF_Clamp`. Both compilers fail the same way on the archive
  and produce the same binary on the dirty tree.
- `ailang_cli.ailang` itself contains the `--haiku` flag.
- `ailang_console.ailang` imports the changed compiler modules.
  `Emit_Syscall` and `Emit_SysInstr` both call `X86_SysInstr` when
  the target is x86-64, so the Linux syscall instruction is the same
  instruction. The Haiku branch is taken only when `Emit.os` is Haiku.

`c_base` cannot emit a Haiku binary. Its `--haiku` column in the
first sweep is a second Linux compile. That column is not the gate.

### 10.4 Haiku self-host

`/tmp/haiku_cc_cross`, guest generation 2, and guest generation 3
are byte-identical. sha256
`1d56f038c1a3a7151f42c21e218d5be059290fd58021f24c3e1bd7f0abbb7235`,
size 7915357. The cross binary was `/tmp/c_new -march=sse2 --haiku
ailang_cli.ailang`. The guest rebuilt it twice with `-march=sse2`.
Checked again after the sweep; the three files still match.

### 10.5 Phase 2 so far

`PlatformProc_SpawnWorker` on Linux is the old worker child: own
process group, `prctl` parent-death signal 15, unblock SIGINT and
SIGTERM (mask 16386), stdout and stderr to `/dev/null`, then exec.
The Linux test's `/bin/echo` produced no output and a process-group
SIGTERM reaped `/bin/sleep` with status 15.
On Haiku the same function is `load_image` plus `resume_thread` plus
`setpgid`. Parent-death is not available. `load_image` does copy the
parent's file descriptors; section 10.10 points the child's stdout
and stderr at `/dev/null` for that copy.
`/tmp/HalCode9000_p2.x` (943707 bytes) is the Linux link of
`HalCode-Haiku/HalCode9000.ailang` with shared UI from `HalCode9000`
and `IPCDispatch` plus `Platform` from this tree. `kill` and `wait4`
in those two files go through `PlatformProc`. A host run of
`--agent deepseek:smoke` with empty stdin exited 1 and logged
`empty stdin — exiting`, after the platform had restored the default
SIGINT and SIGTERM actions. The tool suite has not been rerun. `HalCode-Haiku/UI.ailang` is the headless
stand-in and does not define `UILayout`, so a compile that uses only
this tree's UI fails in `CC_SleepAnimated`. The desk build still
needs that stand-in; the agent compile uses the shared TUI.

### 10.6 Native HalCode binary smoke

`/tmp/c_new -march=sse2 --haiku` produced `/tmp/HalCode9000_haiku.x`,
1033885 bytes, ET_EXEC, entry `0x100000b0`, base `0x10000000`.
Copied to `/boot/home/HalCode9000_haiku` and run as
`--agent deepseek:smoke` with empty stdin. It printed the same three
lines as the Linux binary (`agent mode detected`, `stdin bytes=0`,
`empty stdin — exiting`) and exited 1. The guest stayed up. This is
not the phase 4 gate: no tool call and no provider request.
The stock `./ailang.x` still has no `--haiku` string. It was not
replaced.

That image was built while `Platform/Proc.ailang` imported
`ProcLinux`. Its spawn path is `fork`, which Haiku returns as
`ENOSYS`. The later image is section 10.9.

### 10.7 Linux tool checks after the platform move

`/tmp/t_read_spawn_linux` calls `PlatformProc_SpawnWorker` on
`/tmp/cc_read_ipc.x`, sends `{"method":"schema"}`, then reads
`/tmp/hc_read_sample.txt`. Exit 0. The client uses `Socket.SendMsg`,
so the tool's `Platform.IPC` Linux module still speaks the 4-byte
big-endian framing. The same exit 0 came back after Read's own socket
loop was moved onto `PlatformIPC_SendMsg` and `PlatformIPC_RecvMsg`.

`/tmp/tool_ipc_check.py` then did schema plus one call for Read, Head,
Wc, Stat, and LS. All five printed `OK`. `FAILED 0`. Head returned
`AAA` from a one-line read. Wc returned `lines: 1` for
`HELLO_READ\n`. Stat's text contained `Type:`. LS of `/tmp/hc_ls_dir`
contained `marker.txt`. No tool process was left behind.

There is no separate HalCode9000 tool-suite script in the tree. These
are the checks that were run. They do not start `--mcp`.

### 10.8 Native Read, Head, Wc, Stat, and LS schema

A Haiku port is one queue. `PlatformIPC_SendMsg` on the client writes
the server port an 8-byte reply-port id and then the JSON.
`PlatformIPC_RecvMsg` on the server strips that prefix and writes the
bare JSON back to the reply port. Low-level `Send` / `Recv` are
unchanged, so the earlier port echo still has one direction.
The reply port is named `hc.ReadRep`. The server uses the id from the
message, not `find_port`.

`/tmp/cc_read_haiku` and `/tmp/t_read_haiku` were copied to
`/boot/home`. The client printed `READ_OK` and exited 0. Fifty more
runs printed `CYCLES:50 FAILS:0`. `listport` afterwards showed no
`@halcode/Read` port. The guest stayed up. The serial log stayed
5142 bytes, mtime unchanged.

The same client shape, `tests/t_tool_haiku.ailang`, then ran:

| Tool | Guest result |
|---|---|
| Head `/tmp/hc_head_sample.txt` | `TOOL_OK`, exit 0, content contained `AAA` |
| Wc `/tmp/hc_read_sample.txt` | `TOOL_OK`, exit 0, content contained `lines: 1` |
| Stat `/tmp/hc_read_sample.txt` | `TOOL_OK`, exit 0, content contained `Type:` |
| LS schema only | `SCHEMA_OK`, exit 0 |

`listport` was clear of `halcode` and `ReadRep` after those four.
At that point LS's call was not run on the guest, because `CCLs_Run`
still forked `/bin/ls`. Section 10.10 replaces that call with
`getdents64`. The selectors were restored to `IPCLinux` and
`ProcLinux` after each Haiku compile.

### 10.9 HalCode image with load_image

Rebuilt with `Proc.ailang` importing `ProcHaiku`, then restored the
Linux selector. `/tmp/HalCode9000_haiku.x` is 1033875 bytes, ET_EXEC,
entry `0x100000b0`. The previous image (`/tmp/HalCode9000_haiku_old.x`,
1033885 bytes, saved from `/boot/home/HalCode9000_haiku`) contains no
`mov rax, 40; syscall`. The new image contains one. The immediate
`57` count went from 63 to 61, and the immediate `40` count from 61
to 62. The two remaining shell forks account for the `57`s that are
still there.

Copied to `/boot/home/HalCode9000_haiku.x` and then to
`/boot/home/HalCode9000_haiku` after the old bytes were saved.
`--agent deepseek:smoke`
with empty stdin printed the same init lines and exited 1. The guest
stayed up. The serial log did not grow. No provider request and no
tool call, so this is still not the phase 4 gate. `./ailang.x` was
not replaced.

### 10.10 Guest `--mcp` for groups 1–3

`CC_MCP_DispatchOnDemand`, `IPCDispatch.RegisterTool`, and
`IPCDispatch_TryConnect` call `PlatformIPC`. The host
`IPCDispatch.Dispatch` path and `AgentProxy` still use sockets.
`PlatformIPC_Close` on a client drops the reply port and leaves the
server's listen port alone. A Haiku accept returns the listen id, so
the tool does not close that id.

LS lists with `getdents64` (syscall 217, name at byte 19, reclen at
byte 16). A Linux call on `/tmp/hc_ls_dir` returned
`exit=0\nmarker.txt\n\n[1 lines]`.

Grep, Find, Diff, Du, Edit, Write, and Undo listen through
`PlatformIPC`. Bash and Git still `fork` and `execve` on Linux. When
`fork` fails they `load_image` `/bin/sh` and let the shell write
`/tmp/hc_bash_out` or `/tmp/hc_git_out`, because the new team cannot
be handed a pipe. The Linux fork path is unchanged: schema plus one
call passed for Read, Head, Wc, Stat, LS, Grep, Find, Diff, Du,
Write, Edit, Undo, Bash, and Git (`/tmp/tool_ipc_check2.py` style
checks, bash needle `P3_BASH_OK`, git needle `exit=`). A Write test
appended host undo entry 145; that entry was removed and `HEAD` put
back to 144. Undo's own call was a read-only list.

`/tmp/c_new -march=sse2 --haiku` wrote `/tmp/haiku_p3/`. Every ELF is
ET_EXEC, System V, entry `0x100000b0`. The HalCode image after the
stdio silence change is 1037968 bytes. The Linux HalCode link of the
same sources is `/tmp/HalCode9000_p3.x`, 943685 bytes. Selectors were
restored to `ProcLinux` and `IPCLinux`.

The guest copy is `/boot/home/p3mcp/` with a 14-tool `cc_tools.json`.
`python3 mcp_p3.py` spoke JSONL to `HalCode9000_haiku --mcp`. The
first run returned `OK` for `tools/list` and for one call of each of
the 14 tools, and `READ50 50` with `READ50_BAD 0`, but tool banners
were mixed into stdout (`BAD 64` from those lines only). `load_image`
had copied the parent's stdout. `PlatformProc_SpawnWorker` now dups
`/dev/null` onto fds 1 and 2 around the load and restores the parent.
The rebuilt image's second run printed:

`CALLS 15 BAD 0 READ50 50 READ50_BAD 0 EXIT 0` and `MCP_OK`.

`listport` before and after, excluding the `grep` command line, showed
no `halcode`, `ReadRep`, or `hc.` port. The serial log stayed 5142
bytes. The guest stayed up. The run wrote guest undo entries 6 and 7
for the Write and Edit files under `/tmp`; `HEAD` was restored to 5.

Group 4 was not in that manifest. Section 10.11 is the later run.
Phase 4 is section 10.12. `./ailang.x` was not replaced. No commit was
made.

### 10.11 Guest `--mcp` for group 4

Skills, Olympus, WebFetch, Packager, Vision, Agent, and MCP listen
through `PlatformIPC`. On Linux, `fork` and `HTTP.GetStream` are
unchanged. When `fork` or `HTTP.GetStream` fails, the tool
`load_image`s `/bin/sh` and the shell writes a capture file. Agent's
outbound Pgmem connect and MCP's two outbound connects still use
sockets. Pgmem and Relmem were copied into this tree from
`/home/bob/HalCode9000/cc_tools/`. Those originals were not edited.
`socket` is still `ENOSYS`, so `PG_ConnectUnix` returns 0. The Haiku
copies do not call `PG_Query` on that zero connection. They
`load_image` `/bin/sh`, and the shell runs one `psql` statement
against `/tmp/.s.PGSQL.5432`, then the tool sends `SIGKILL` and waits.
When the socket connect succeeds, the Linux path is unchanged.

`/tmp/c_new -march=sse2 --haiku` wrote `/tmp/g4h/`. Every ELF is
ET_EXEC, System V, entry `0x100000b0`. Selectors were restored to
`ProcLinux` and `IPCLinux`. HalCode itself was not rebuilt. The guest
binary is still `/boot/home/p3mcp/HalCode9000_haiku`, 1037968 bytes.
The guest `cc_tools.json` for this run lists only these nine tools.

Linux schema plus one call passed for all nine (`/tmp/tool_ipc_g4.py`).
Host Pgmem and Relmem did not return `postgres unavailable`, so that
machine's database accepted the connection. The guest postmaster
listens on `/tmp/.s.PGSQL.5432`. Peer auth is the OS user `user`,
database `ailang_system`, project `HalCode9000` id `1`. A native
`socket` call still returns `ENOSYS`.

The first guest run returned `OK` for tools/list, Skills, WebFetch,
Packager, Vision, Agent, and MCP, and `UNAVAILABLE` for Pgmem and
Relmem. Olympus returned `exit=128` with an empty body: the capture
redirect was attached to the last command of an `&&` list, so
`echo '=== branch ==='` never reached the file, and `git log` on the
empty repo exited 128. The image path now runs `{ cmd; } > file`.
The rebuilt Olympus passed, and the Linux fork path still returns
`=== branch ===`.

The second guest run printed:

`OK` tools/list, Skills (`cat/p3name`), Olympus (`=== branch ===`),
WebFetch (`WEBFETCH_OK` from `file:///tmp/hc_fetch_body.txt`),
Packager (`hello.ailang`), Vision (`image/png` on a 1x1 PNG,
`detail=metadata`), Agent (`Worker spawned asynchronously`), MCP
(`[MCP Bridge] Received request for tool: P3MCP`).

Pgmem pickup and Relmem status printed `UNAVAILABLE`. The text is
`postgres unavailable`. No SQL query ran.

Each of the nine was then called 50 more times:
`Agent50 50 BAD 0`, `MCP50 50 BAD 0`, `Olympus50 50 BAD 0`,
`Packager50 50 BAD 0`, `Pgmem50 50 BAD 0`, `Relmem50 50 BAD 0`,
`Skills50 50 BAD 0`, `Vision50 50 BAD 0`, `WebFetch50 50 BAD 0`.
`CALLS 10 BAD 0 EXIT 0` and `MCP_OK`.

The Agent command is `./HalCode9000.x --agent`. That file is not in
`/boot/home/p3mcp`, so the shell exits and the team is reaped. No
provider turn was started.

`listport` saved to a file had 285 lines and no `halcode`, `ReadRep`,
or `hc.` port. Guest undo `HEAD` stayed 5. The serial log stayed
5142 bytes. The guest stayed up.

Guest `psql` runs the first statement of a `-f` file and then does not
exit. A multi-statement boot never reached `SELECT id`. The first run
on the `psql` fallback printed `no project id`. Boot is now only
`SELECT id::text FROM hc_projects WHERE name='HalCode9000'`. Stderr
fails the call only when it contains `ERROR` or `FATAL`. The
`hc_symbol_edges` catalog warnings stay warnings. The next fallback
run returned Pgmem `not found` and Relmem
`0 files, 0 symbols, 0 edges`: the seed file's first statement was
`CREATE TABLE`, so the `PGMEM_OK` row was never inserted.

The following run inserted that row as its own statement and read
it back before `--mcp` started. It printed `HEAD 5`, `ROW` `PGMEM_OK`,
`COUNT` `0 files, 0 symbols, 0 edges`, `OK` tools/list, `OK Pgmem`,
`OK Relmem`, `EXIT 0 BAD 0`, then `Pgmem50 50 Relmem50 50`,
`HEAD_AFTER 5`, and `MCP_OK`. `SSH_RC:0`.

`listport` saved to a file had 285 lines and no `halcode`, `ReadRep`,
or `hc.` port. `pidof psql` was empty. The serial log stayed 5142
bytes. The guest stayed up. The `p3g4` row was deleted after the 50
calls. A leftover `hc_p3_probe` table from an earlier probe was
dropped. Pickup and status do not write the undo journal. `HEAD`
stayed 5.

Sleep, Ailang, AilangLSP, and JS are not in the phase 3 list and were
not ported. Phase 3 is complete. Phase 4 is section 10.12. No commit
was made.

### 10.12 Guest agent turn

The leak checks ran before the provider request. `/tmp/t_spawn_stdio_haiku.x`
printed `STDIO_OK` and exited 0. `/tmp/t_http_leak_haiku.x` printed
`HTTP_OK` and exited 0 while a second curl was still alive: the first
`file://` stream reached EOF and its exit code was 0. `pidof curl` was
empty after that test. The serial log was still 5142 bytes.

`/tmp/c_new -march=sse2 --haiku` wrote `/tmp/HalCode9000_p4_haiku.x`,
1066930 bytes, ET_EXEC, System V, entry `0x100000b0`. The five
selectors were restored to `ProcLinux`, `IPCLinux`, `HTTPLinux`,
`FanLinux`, and `AgentLinux`. `Signal` stayed `SignalLinux`. The
headless `UI.ailang` was restored. `./ailang.x` was not replaced.
`/boot/home/p3mcp/HalCode9000_haiku` was not replaced.

The image was copied to `/boot/home/p4gate/HalCode9000_p4`. That
directory's `cc_tools.json` lists only Read: `./cc_read_ipc.x` on
`@halcode/Read`. The worker is the native Read binary from
`/boot/home/p3mcp` (206180 bytes). A direct run printed
`runtime_loader: Failed to get gcc version` and still created the
`@halcode/Read` port. That port was gone before the agent started.
`listport` then had 285 lines and no `@` port.

`/boot/home/.halcode/providers` is absent, so the built-in DeepSeek
entry was used. The spec was `deepseek:deepseek-flash`. The key file
was 35 bytes. The prompt was 135 bytes and did not contain the token.
`/tmp/p4_gate.txt` was `P4_GATE_OK_7f3c` plus a newline.

The process exited 0. Stderr recorded `cred bytes=35`,
`ConnectProxy=1` (the Haiku attach return, which is schema boot), and
`CCFan self-test sum=0`. The debug log recorded two
`HTTP status=200` lines, `GetToolName done: Read`, one dispatch
return, then `No tools requested`. `reply.txt` was 15 bytes,
`P4_GATE_OK_7f3c`. No second tool name appeared.

`pidof curl`, `pidof HalCode9000_p4`, and `pidof cc_read_ipc.x` were
empty. `listport` saved to a file had 287 lines and no `halcode`,
`ReadRep`, `hc.`, or `@` port. Guest undo `HEAD` stayed `5`. The
serial log stayed 5142 bytes, mtime unchanged. The guest stayed up.
`ps` was not used.

Section 7, Sleep, Ailang, AilangLSP, JS, and the Pgmem operations were
not in this build. `spawn_thread` was not added. Phase 5 was not
started. No commit was made.
