# HalCode on Haiku

Prebuilt native package for Haiku R1/beta6, x86_64. The `1.0.0` in
`halcode-haiku-1.0.0-x86_64.tar.gz` is the string `ailang_haiku -v`
prints (`AILANG 1.0.0`). It is not a separate HalCode version.

The default install copies the binaries in this tarball. It does not
compile. It does not install the desk, the window, or `sys_compat_run`.

## Requirements

- Haiku R1/beta6 on x86_64. `uname -s` is `Haiku` and `uname -m` is
  `x86_64`. Other machines stop before any copy.
- `curl` on `PATH`. If it is missing, the installer stops and prints
  `pkgman install curl`.
- Universal Ctags, package name `ctags`. If `ctags` is not on `PATH`,
  the installer runs `pkgman install -y ctags`. If that fails it
  continues and prints the warning in the Relmem section below.
- A home directory. Files go under `$HOME/config/non-packaged`. The
  script does not hard-code `/boot/home`.
- Enough free space for the compiler, `Librarys/` (about 27 MB), the
  agent, the analyzer, and 24 workers.
- A provider key only if you run `--agent`. Hints are `deepseek`,
  `anthropic`, and `xai`.

PostgreSQL is optional. `./install.sh` without `--skip-postgres` runs
`scripts/haiku_postgres.sh`, which needs `gcc` and `pkgman` when those
pieces are not already present. Pgmem park, search, and index still
report `postgres unavailable` on this native build. Pickup and a Relmem
status query were measured. `--skip-postgres` skips that step.

## Install

Check the archive, unpack it, and run the script from its directory:

```
sha256sum -c halcode-haiku-1.0.0-x86_64.tar.gz.sha256
tar xf halcode-haiku-1.0.0-x86_64.tar.gz
cd halcode-haiku-1.0.0-x86_64
./install.sh --skip-keys --skip-postgres
```

`./install.sh` with no flags asks for the three keys and runs the
PostgreSQL boot script. Enter at a key prompt keeps an existing file
and writes nothing new. A pasted key is stored as
`~/.halcode/<hint>_key` with mode 600. The directory is mode 700.
`--skip-keys` writes no key files.

The script is safe to run twice. If `bin/` is not already on `PATH`,
one line is appended to `$HOME/config/settings/profile`:

```
export PATH="$HOME/config/non-packaged/bin:$PATH"
```

A second run does not add it again. Open a new terminal, or run that
export, before you type `halcode`.

What is installed:

- `$HOME/config/non-packaged/bin/halcode`
- `$HOME/config/non-packaged/bin/ailang_haiku` and `Librarys/` beside it
- `$HOME/config/non-packaged/bin/ailang_haiku.sha256`
- `$HOME/config/non-packaged/bin/analyzer_haiku`
- `$HOME/config/non-packaged/lib/halcode/HalCode9000.x`
- the 24 workers and `cc_tools.json` in that same directory

`./install.sh --build` is the compile path. It needs the HalCode source
tree (`scripts/stage_platform.sh`). This tarball does not contain that
tree, so `--build` exits before any compile.

## Run

`halcode` with no arguments, `-h`, or `--help` prints how to start and
exits 0. It does not open a full-screen terminal UI.

```
halcode --mcp
printf '%s\n' 'Read README-HAIKU.md' | halcode --agent deepseek:deepseek-flash
```

The prompt for `--agent` is stdin. Empty stdin exits 1. That command
spends one provider turn. The Agent tool can start another turn. Do
not run it unless you mean to.

Compile and analyze from a shell:

```
ailang_haiku --haiku source.ailang out.x
analyzer_haiku source.ailang
```

A clean analyze prints `Summary: 0 errors`. A native program's entry
is `0x100000b0`.

## What works

Headless `--mcp` and `--agent`. Native compile with `--haiku` and one
analyze. These 24 tools:

Read, Head, LS, Write, Bash, WebFetch, Relmem, Pgmem, Agent, Edit,
Undo, Find, Grep, Git, Stat, Wc, Du, Diff, Olympus, MCP, Skills,
Ailang, Packager, Vision.

Pgmem pickup and Relmem status return a real query. Relmem indexes
symbols when `ctags` is on `PATH`.

## What does not work

- The full-screen terminal UI. Linux ioctl 16 is not translated, so
  raw mode cannot be set. A no-argument launch does not enter it.
- The desk and the window. They are not in this package. Do not run
  HalCode through `sys_compat_run`. Killing a bridged process that is
  blocked in `read()` panics the kernel.
- Sleep, AilangLSP, and JS. They use Unix sockets. `socket` stays
  `ENOSYS` on purpose.
- Pgmem park, search, and index. They still report
  `postgres unavailable`.
- `ailang_haiku -v` as a build check. See below.

## Known issues

Starting a native `--haiku` program from a shell prints:

```
runtime_loader: Failed to get gcc version
```

The program still runs. Haiku's `runtime_loader` asks the image for a
gcc version, and this compiler does not record one. Leave
`runtime_loader` alone. The agent starts tools with `load_image`, which
does not print that line.

`ailang_haiku -v` prints `AILANG 1.0.0`. That string is `FixedPool.AilVer`
(major 1, minor 0, patch 0) and is not a build id. A compiler from
2026-08-31 prints the same line, so comparing `-v` cannot tell a stale
binary from the tree this tool was built with. No build id was added.

`install.sh` writes `ailang_haiku.sha256` beside `ailang_haiku`. The
`halcode` launcher warns when that stamp is missing or does not match
the binary. The Ailang tool was not rebuilt to read the stamp. It looks
up `ailang_haiku` and `analyzer_haiku`, never `ailang.x`, and the Haiku
build passes `--haiku` on compile. `Librarys/` has to sit beside that
compiler path, because the compiler takes Librarys from the directory
of argv[0] when `AILANG_LIB_PATH` is unset. A symlink in `bin/` does
not count: Haiku's readlink of the program path returns argv[0] and
does not resolve the link, so the installer copies the compiler.

The Haiku install writes `config/system_prompt.haiku.txt` to
`~/.halcode/system_prompt.txt`. That prompt says the agent is native
on Haiku, names `ailang_haiku` and `analyzer_haiku`, and does not tell
the model to use Sleep or the Linux bridge. The Linux file
`config/system_prompt.txt` is unchanged. The loader reads the file in
`~/.halcode`. It does not ask the runtime which operating system it is.

Relmem indexes symbols with `ctags`. HaikuPorts ships Universal Ctags
as the package `ctags`. If `pkgman` is missing or the package does not
install, the script keeps going and prints:

```
WARNING: universal-ctags is not installed. Relmem will index 0 symbols until ctags is on PATH.
```

Without `ctags`, Relmem reports 0 symbols. That is the missing indexer,
not an empty tree.

## Feedback

Open an issue at
https://github.com/AiLang-Author/HalCode-Haiku/issues

Copyright 2026 Sean Collins, 2 Paws Machine and Engineering. MIT.
