---
name: haiku-porting
description: Linux-to-Haiku porting patterns — POSIX gaps, API replacements, HaikuPorts recipes. Load when porting Linux/Unix software to Haiku, writing cross-platform code targeting Haiku, creating HaikuPorts build recipes, or encountering Haiku-specific build failures. Use whenever the user mentions porting to Haiku, BeOS compatibility, HaikuPorts, recipe files, cross-platform Haiku, POSIX on Haiku, or adapting Linux code for Haiku.
---

# Linux → Haiku Porting Guide

## OVERVIEW

Haiku has a mostly-POSIX-compliant userland, so most well-written portable C/C++
builds with minor changes. The friction points are Linux-specific APIs that have
no POSIX equivalent and Haiku's own native APIs that replace them.

**Rule of thumb:** if the Linux code uses `epoll`, `inotify`, `timerfd`,
`signalfd`, `eventfd`, `io_uring`, `/proc`, or `netlink` — those do not exist
on Haiku and must be replaced.

---

## WHAT HAIKU HAS

| Layer | Status |
|-------|--------|
| POSIX threads (pthread) | Full support |
| BSD sockets | Full (IPv4, IPv6, Unix domain) |
| poll() / select() | Supported |
| dlopen / dlsym / dlclose | Supported (thin wrappers over native API) |
| fork() / exec() | Supported with caveats (see below) |
| POSIX signals | Mostly compatible |
| mmap | Supported (but prefer areas for shared memory) |

## WHAT HAIKU DOES NOT HAVE

| Linux API | Haiku Replacement | Section |
|-----------|-------------------|---------|
| epoll | poll() or BLooper message pump | Event Loops |
| inotify | BNodeMonitor + watch_node() | File Monitoring |
| timerfd / signalfd / eventfd | BMessageRunner / BLooper timers | Event Loops |
| io_uring | No equivalent; use poll() + threads | — |
| /proc filesystem | No equivalent; use kernel kit APIs | Process Info |
| netlink sockets | No equivalent | — |
| ipc: sysv shmem | Areas (create_area / clone_area) | IPC |
| sysv semaphores | Haiku semaphores (create_sem) | IPC |
| sysv message queues | Haiku ports (create_port) | IPC |
| abstract unix sockets | Supported — same as Linux | — |

---

## EVENT LOOPS

### Replacing epoll

Haiku has `poll()` and `select()` but **not** `epoll`. For most server code,
`poll()` is a direct drop-in:

```cpp
// Linux                          // Haiku
#include <sys/epoll.h>            #include <poll.h>
epoll_create1(0)                  // just use struct pollfd[]
epoll_ctl(epfd, ADD, fd, &ev)     // add to pollfd array
epoll_wait(epfd, events, n, ms)   poll(fds, nfds, timeout_ms)
```

For GUI applications, the idiomatic approach is a **BLooper message pump** —
BLooper runs its own thread and dispatches BMessages. File descriptors can be
bridged into the message system using a worker thread that poll()s and posts
BMessages.

### Replacing timerfd

Use `BMessageRunner` to post periodic BMessages to a BLooper/BHandler:

```cpp
BMessageRunner *timer = new BMessageRunner(
    BMessenger(myHandler),
    new BMessage(MSG_TICK),
    500000  // interval in microseconds
);
```

Or use `BLooper::SetPulseRate()` for simple periodic callbacks via
`BView::Pulse()`.

---

## FILE MONITORING

### Replacing inotify with BNodeMonitor

```cpp
#include <NodeMonitor.h>

// Watch a file for changes (name, stat, attributes)
node_ref nref;
entry.GetNodeRef(&nref);  // from a BEntry

watch_node(&nref, B_WATCH_ALL, myHandler);
// B_WATCH_ALL = B_WATCH_NAME | B_WATCH_STAT | B_WATCH_ATTR | B_WATCH_DIRECTORY
```

The handler receives BMessages with `what` field set to `B_NODE_MONITOR` and
an `opcode` field:

| Opcode | Value | Equivalent inotify |
|--------|-------|--------------------|
| B_ENTRY_CREATED | 1 | IN_CREATE |
| B_ENTRY_REMOVED | 2 | IN_DELETE |
| B_ENTRY_MOVED | 3 | IN_MOVED_FROM + IN_MOVED_TO |
| B_STAT_CHANGED | 4 | IN_MODIFY / IN_ATTRIB |
| B_ATTR_CHANGED | 5 | (no inotify equiv — Haiku extended attrs) |
| B_DEVICE_MOUNTED | 6 | (mount monitoring) |
| B_DEVICE_UNMOUNTED | 7 | (unmount monitoring) |

Watch flags:

| Flag | Value | Purpose |
|------|-------|---------|
| B_WATCH_NAME | 0x0001 | Entry creation/deletion/rename |
| B_WATCH_STAT | 0x0002 | stat changes (size, times, perms) |
| B_WATCH_ATTR | 0x0004 | Extended attribute changes |
| B_WATCH_DIRECTORY | 0x0008 | Directory entry list changes |
| B_WATCH_ALL | 0x000f | All of the above |
| B_WATCH_MOUNT | 0x0010 | Volume mount/unmount |
| B_WATCH_CHILDREN | 0x0040 | Watch entries in directory recursively |

Stop watching:
```cpp
stop_watching(myHandler);  // or stop_watching(BMessenger)
```

---

## PROCESS CREATION

### fork() caveats

`fork()` works but **areas** (Haiku shared memory regions) are NOT inherited
by the child. Use `fork()` only for immediate `exec()` patterns (fork+exec).

For spawning new processes, prefer `load_image()`:
```cpp
#include <image.h>

const char *argv[] = { "/bin/ls", "-la", NULL };
thread_id tid = load_image(2, argv, environ);
resume_thread(tid);  // process starts suspended

status_t exitVal;
wait_for_thread(tid, &exitVal);
```

### spawn_thread for native threads

```cpp
#include <OS.h>

int32 my_thread(void *data) {
    // thread body
    return 0;
}

thread_id tid = spawn_thread(my_thread, "worker", B_NORMAL_PRIORITY, NULL);
resume_thread(tid);
```

Threads start **suspended** — always call `resume_thread()`.

---

## DYNAMIC LOADING

### dlopen → load_add_on

Both work on Haiku. `dlopen` is a POSIX wrapper, but the native API is:

```cpp
#include <image.h>

image_id addon = load_add_on("/path/to/addon.so");
if (addon < 0) { /* error */ }

void (*func)();
status_t err = get_image_symbol(addon, "my_function",
    B_SYMBOL_TYPE_TEXT, (void **)&func);

func();
unload_add_on(addon);
```

Symbol type constants:
- `B_SYMBOL_TYPE_TEXT` (0x2) — functions
- `B_SYMBOL_TYPE_DATA` (0x1) — global variables
- `B_SYMBOL_TYPE_ANY` (0x5) — either

---

## IPC PRIMITIVES

Haiku has three native IPC mechanisms beyond POSIX:

### Areas (shared memory)

```cpp
void *addr;
area_id area = create_area("shared_buf", &addr, B_ANY_ADDRESS,
    4096, B_NO_LOCK, B_READ_AREA | B_WRITE_AREA);

// Other process:
area_id clone = clone_area("clone_buf", &addr, B_ANY_ADDRESS,
    B_READ_AREA, area);
// or by name:
area_id found = find_area("shared_buf");
```

### Ports (message queues)

```cpp
port_id port = create_port(100, "my_port");

int32 code = 42;
write_port(port, code, buffer, bufferSize);

int32 recv_code;
read_port(port, &recv_code, buffer, bufferSize);  // blocks

delete_port(port);
```

### Semaphores

```cpp
sem_id sem = create_sem(1, "my_lock");
acquire_sem(sem);   // blocks if count <= 0
release_sem(sem);
delete_sem(sem);
```

---

## FILESYSTEM DIFFERENCES

- **BFS** is case-sensitive (unlike HFS+ on macOS)
- BFS supports **extended attributes** natively — use `BNode::ReadAttr()` /
  `BNode::WriteAttr()` or the `fs_attr` POSIX extensions
- No `/proc` — use `get_team_info()`, `get_thread_info()`, etc.
- No `/etc` or `/usr` — use `find_directory()`:

```cpp
#include <FindDirectory.h>
#include <Path.h>

BPath path;
find_directory(B_USER_SETTINGS_DIRECTORY, &path);
// path = /boot/home/config/settings

find_directory(B_SYSTEM_LIB_DIRECTORY, &path);
// path = /boot/system/lib
```

Key directory constants:

| Constant | Typical path | Use for |
|----------|-------------|---------|
| B_USER_SETTINGS_DIRECTORY | /boot/home/config/settings | App config files |
| B_SYSTEM_APPS_DIRECTORY | /boot/system/apps | Installed apps |
| B_SYSTEM_LIB_DIRECTORY | /boot/system/lib | Shared libraries |
| B_USER_DIRECTORY | /boot/home | Home directory |
| B_APPS_DIRECTORY | /boot/system/apps | Global apps |
| B_SYSTEM_DIRECTORY | /boot/system | System root |

**Never hardcode paths.** Always use `find_directory()` at runtime.

CLI equivalent: `finddir B_USER_SETTINGS_DIRECTORY`

---

## NETWORK

BSD sockets work identically. No portability issues for socket-based code.

**Missing:** `netlink` sockets (Linux kernel communication). If the code uses
`AF_NETLINK` for route table or interface enumeration, replace with Haiku's
network interfaces API or `ifconfig` parsing.

---

## SIGNALS

Mostly POSIX-compatible. Differences:
- `SIGRT*` (real-time signals) — not available
- Signal delivery to threads follows POSIX semantics
- `sigaction()` works normally

---

## COMPILER & BUILD SYSTEM

Haiku ships **GCC** (both gcc2 for BeOS compat and modern gcc) and **clang**.

### Common configure flags

```bash
./configure --prefix=/boot/system/non-packaged
# or for packaged builds via HaikuPorts:
runConfigure ./configure
```

### pkg-config

Works normally. Haiku packages install `.pc` files in standard locations.

### CMake

```bash
cmake -DCMAKE_INSTALL_PREFIX=/boot/system/non-packaged ..
```

### Platform detection

```cpp
#ifdef __HAIKU__
// Haiku-specific code
#endif
```

In autoconf: `*-*-haiku*` in `config.sub` / host triple.

---

## HAIKUPORTS RECIPES

For packaging ported software, write a `.recipe` file. See
`references/posix-map.md` for the full POSIX mapping table. Recipe format
overview:

```bash
SUMMARY="Short description"
DESCRIPTION="Longer description"
HOMEPAGE="https://example.com"
COPYRIGHT="2024 Author"
LICENSE="MIT"
REVISION="1"
SOURCE_URI="https://example.com/foo-$portVersion.tar.gz"
CHECKSUM_SHA256="abc123..."
ARCHITECTURES="all !x86_gcc2"

PROVIDES="
    foo = $portVersion
    cmd:foo = $portVersion
    "
REQUIRES="
    haiku
    lib:libz
    "
BUILD_REQUIRES="
    haiku_devel
    devel:libz
    "
BUILD_PREREQUIRES="
    cmd:gcc
    cmd:make
    "

BUILD()
{
    runConfigure ./configure
    make $jobArgs
}

INSTALL()
{
    make install
}
```

Key variables in BUILD()/INSTALL():
- `$sourceDir` — unpacked source
- `$prefix`, `$binDir`, `$libDir`, `$includeDir`, `$dataDir`, `$manDir`
- `$jobArgs` — parallel make flags
- `$portVersion`, `$portName`

Helper functions:
- `runConfigure` — invokes configure with correct Haiku paths
- `packageEntries <suffix> <files>` — split files into sub-packages
- `prepareInstalledDevelLibs <name>` — organize lib + devel split
- `fixPkgconfig` — fix .pc file paths
