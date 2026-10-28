# Fix: IPCDispatch_Respawn empty-envp crash on worker restart

Status: **fixed + built** (pending live restart via `--self-update`)

## TL;DR

`IPCDispatch_Respawn` forked dead `cc_*_ipc.x` workers with an **empty
environment** (`envp = Allocate(8); StoreValue(envp, 0)`), unlike the
first-boot path `CC_LaunchTool` which passes the full inherited environment
via `CC_BuildInheritedEnv`. A respawned worker therefore crashed during
startup, producing the observed **"tool crash + failure to restart"** loop.
Respawn also omitted the stdout/stderr redirect and PID tracking that
`CC_LaunchTool` already does. All three gaps are now closed.

## Root cause

Two launch paths for the same worker binaries:

| | First boot | Respawn |
|---|---|---|
| Function | `CC_LaunchTool` (HalCode9000.ailang) | `IPCDispatch_Respawn` (IPCDispatch.ailang) |
| envp | full (`CC_BuildInheritedEnv` → `/proc/self/environ`) | **empty** |
| stdout/stderr | redirected to `/dev/null` | **not redirected** |
| PID tracking | recorded in `CCRunState.child_pids` | **not recorded** |

The `cc_*_ipc.x` workers read `PATH`, `HOME`, `HALCODE_*` and backend
credentials from the environment at startup. An empty `envp` makes them die
before they bind their socket, so `IPCDispatch_Reconnect`'s retry loop can
never reconnect.

## What changed

File: `IPCDispatch.ailang` (applied to **both** trees — see below).

1. **New `IPCDispatch_BuildEnvp`** — mirrors `CC_BuildInheritedEnv`:
   reads `/proc/self/environ` in the parent *before* `fork`, then builds a
   NUL-terminated `char*[]` for `execve`.

2. **`IPCDispatch_Respawn` rewritten** to:
   - build the full inherited envp before `fork` (COW-shared with child),
   - redirect child stdout/stderr to `/dev/null` (same as first boot),
   - keep `PR_SET_PDEATHSIG(SIGTERM)` (already present),
   - record the forked PID.

3. **PID tracking + reap**:
   - added `respawn_pids` / `respawn_count` to the `IPCDState` fixed pool,
   - `IPCDispatch.Shutdown` now SIGTERMs, waits, and SIGKILLs stragglers for
     every tracked respawned PID (mirrors `CC_KillAllChildren`), closing the
     WSL2 `PDEATHSIG`-unreliable leak.

## Two-tree note (important)

The GTK repo (`~/HalCodeGTK`) builds its own `HalCode9000.ailang`, but its
`Import.Applications.HalCode9000.IPCDispatch` resolves through the
`~/Ailang-Self-Hosting-/Applications/HalCode9000 -> ~/HalCode9000` symlink to
the **canonical** tree. Verified empirically: a `--no-tools --no-copy` build
only contained the new `"respawn FAIL build_envp"` string after the canonical
copy was updated.

So the fix was applied to **both**:

- `~/HalCodeGTK/IPCDispatch.ailang`
- `~/HalCode9000/IPCDispatch.ailang`

(`diff` confirms the two are byte-identical after the change.)

## Build / deploy

```bash
cd ~/HalCodeGTK
./build.sh --self-update
```

This rebuilds everything to `/tmp`, stops the running GTK app
(`halcode_desk.x`, `halcode_shell_g`, `HalCode9000.x --host/--agent`),
atomically swaps the project-root binaries, and relaunches the app. The
long-lived `--mcp` servers in the other tree are left untouched.

## Verification

```bash
# after a --no-copy build, the fix must be present in the main binary:
grep -a -c "respawn FAIL build_envp" /tmp/HalCode9000.x   # -> 1
```

Runtime check (after restart): kill a `cc_*_ipc.x` worker and confirm the
`--host` parent respawns it and reconnects instead of logging a crash loop.

## Next

- Serve mode lives in the HalBot repo, not this tree.
