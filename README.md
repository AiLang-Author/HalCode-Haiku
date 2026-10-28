# HalCode-Haiku

Native Haiku window for **HalCode9000**. The agent, tools, providers, and
`~/.halcode` keys are the same as
[HalCode9000](https://github.com/AiLang-Author/HalCode9000) and
[HalCodeGTK](https://github.com/AiLang-Author/HalCodeGTK).

The desk (`shell/halcode_desk.x`) is an AILang Linux ELF. The
[Haiku Linux bridge](https://github.com/AiLang-Author/Haiku-Linux-bridge)
runs it. The window is a Haiku `BWindow`: it blits `frame.raw` through
`app_server` and writes mouse and key events back as files. There is no
GTK shell in this tree.

Copyright (c) 2026 Sean Collins, 2 Paws Machine and Engineering. MIT.

## Pieces

| Piece | Where it runs |
|---|---|
| `HalCode9000.x` and `cc_*_ipc.x` | Linux ELF, via the bridge |
| `shell/halcode_desk.x` | Linux ELF, via the bridge. Draws the chat. |
| `shell/halcode_shell_haiku` | Haiku. `g++ -lbe`. Shows the frame. |

## Build the agent and the desk

On the Linux machine, with `ailang.x` on `PATH`:

```bash
./install.sh --no-desktop
```

That builds the agent and `shell/halcode_desk.x`. It does not build the window.

## Build the window

On Haiku, inside this tree:

```bash
make -C shell
./scripts/launch_halcode.sh
```

`launch_halcode.sh` starts the desk with `sys_compat_run` when that loader
is on `PATH` (or `$SYS_COMPAT_RUN`), then opens the Haiku window on
`/tmp/halcode_app`.

Command+Q, or File → Quit, writes `quit` and closes the window.
