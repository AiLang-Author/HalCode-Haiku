# HalCode Haiku window

Two processes:

- `halcode_desk.x` — AILang desk. AppDesk MDI, fonts, framebuffer. A Linux ELF. The Haiku Linux bridge runs it.
- `halcode_shell_haiku` — native Haiku window (`BApplication` / `BWindow` / `BBitmap`). No GTK.

```
make -C shell desk          # on the Linux build machine, needs ailang.x
make -C shell               # on Haiku: g++ -lbe
```

State directory `/tmp/halcode_app`:

| File | Meaning |
|---|---|
| `meta.bin` | int32 width, height, pitch |
| `frame.raw` | BGRA |
| `gen.txt` | generation; the window reloads on change |
| `ptr.txt` | `d`/`m`/`u`/`w`/`W` x y, frame pixels |
| `keys.txt` | one key command |
| `cmd.txt` | `quit` |
| `paste.txt` | clipboard text into the desk |
| `copy.txt` | desk text onto the Haiku clipboard |

Drag title bars, resize the grip, and type in the chat the desk draws. Command+Q or File → Quit stops the window and writes `quit`.
