---
name: tmux-interactive
description: Run interactive CLI tools (REPLs, full-screen apps, commands that require a real terminal) via tmux when the Bash tool isn't enough. Use for vim, interactive git rebase, Python REPL, gdb, etc.
---

# Interactive Commands via tmux

Use when the Bash tool hangs because a command expects a real terminal (readline, full-screen UI, interactive prompts).

## Quick Reference

```bash
# Start
tmux new-session -d -s <name> <command>
# Send input
tmux send-keys -t <name> 'text' Enter
# Read screen
tmux capture-pane -t <name> -p
# Kill
tmux kill-session -t <name>
```

## WSL2 Notes

- tmux works fine in WSL2 — no special setup needed
- Use `/bin/bash` as shell if the default shell causes issues: `tmux new-session -d -s s /bin/bash`
- Sessions persist across Bash tool calls — always kill when done

## Core Pattern

```bash
# 1. Start
tmux new-session -d -s mysess vim /tmp/edit.txt
sleep 0.3                                    # let it init

# 2. Interact
tmux send-keys -t mysess 'i' 'hello world' Escape ':wq' Enter

# 3. Capture output to verify
tmux capture-pane -t mysess -p

# 4. Clean up
tmux kill-session -t mysess
```

## Special Keys

`Enter`, `Escape`, `C-c`, `C-x`, `Up`, `Down`, `Left`, `Right`, `Space`, `BSpace`

## Common Cases

### Python REPL
```bash
tmux new-session -d -s py python3 -i
sleep 0.2
tmux send-keys -t py 'import sys; print(sys.version)' Enter
tmux capture-pane -t py -p
tmux kill-session -t py
```

### Interactive git
```bash
tmux new-session -d -s rebase -c /repo git rebase -i HEAD~3
sleep 0.5
tmux capture-pane -t rebase -p   # see editor state
tmux send-keys -t rebase ':wq' Enter
tmux kill-session -t rebase
```

## Mistakes to Avoid

- **Don't capture immediately** — add `sleep 0.2-0.5` after `new-session` before first capture
- **Enter is a separate arg** — `send-keys -t s 'cmd' Enter`, not `'cmd\n'`
- **Always kill** — orphaned sessions accumulate; check with `tmux list-sessions`
- **Don't use for simple commands** — if Bash tool handles it, don't reach for tmux
