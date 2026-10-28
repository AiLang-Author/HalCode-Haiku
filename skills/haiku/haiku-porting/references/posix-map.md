# Linux → Haiku API Mapping Table

Comprehensive mapping of Linux-specific and POSIX APIs to their Haiku equivalents.
Load this reference when you need the exact replacement for a specific Linux API.

---

## Event & I/O Multiplexing

| Linux API | Haiku Equivalent | Notes |
|-----------|-----------------|-------|
| `epoll_create` / `epoll_ctl` / `epoll_wait` | `poll()` or BLooper | No epoll on Haiku; poll() is the direct replacement; BLooper for GUI |
| `select()` | `select()` | Fully supported |
| `poll()` | `poll()` | Fully supported |
| `inotify_init` / `inotify_add_watch` | `watch_node()` + BNodeMonitor | Handler receives B_NODE_MONITOR BMessages |
| `timerfd_create` / `timerfd_settime` | `BMessageRunner` or `set_alarm()` | BMessageRunner posts periodic BMessages |
| `signalfd()` | No direct equiv | Handle signals in signal handlers, post BMessages |
| `eventfd()` | Haiku port or pipe | `create_port()` for cross-thread notification |
| `io_uring` | No equivalent | Use poll() + thread pool |

## File Monitoring (inotify → BNodeMonitor)

| inotify Event | Haiku Opcode | Value | watch_node() Flag |
|---------------|-------------|-------|-------------------|
| IN_CREATE | B_ENTRY_CREATED | 1 | B_WATCH_DIRECTORY (0x0008) |
| IN_DELETE | B_ENTRY_REMOVED | 2 | B_WATCH_DIRECTORY (0x0008) |
| IN_MOVED_FROM / IN_MOVED_TO | B_ENTRY_MOVED | 3 | B_WATCH_DIRECTORY (0x0008) |
| IN_MODIFY / IN_ATTRIB | B_STAT_CHANGED | 4 | B_WATCH_STAT (0x0002) |
| (no equivalent) | B_ATTR_CHANGED | 5 | B_WATCH_ATTR (0x0004) |
| (mount events) | B_DEVICE_MOUNTED | 6 | B_WATCH_MOUNT (0x0010) |
| (mount events) | B_DEVICE_UNMOUNTED | 7 | B_WATCH_MOUNT (0x0010) |

## Process & Thread Management

| Linux API | Haiku Equivalent | Notes |
|-----------|-----------------|-------|
| `fork()` | `fork()` | Works, but areas NOT inherited; use for fork+exec only |
| `exec*()` | `exec*()` | Fully supported |
| `posix_spawn()` | `load_image()` | Native: returns thread_id, starts suspended |
| `waitpid()` | `wait_for_thread()` | For load_image'd processes |
| `pthread_create()` | `pthread_create()` or `spawn_thread()` | Both work; spawn_thread is native |
| `pthread_mutex_*` | `pthread_mutex_*` | Fully supported |
| `pthread_cond_*` | `pthread_cond_*` | Fully supported |
| `pthread_rwlock_*` | `pthread_rwlock_*` | Fully supported |
| `clone()` | No equivalent | Use spawn_thread() |
| `getpid()` | `getpid()` | Works; Haiku calls processes "teams" |
| `/proc/self/exe` | `get_image_info(0, &info)` then `info.name` | No /proc on Haiku |
| `/proc/<pid>/cmdline` | `get_team_info()` | Access via Kernel Kit |
| `/proc/<pid>/status` | `get_thread_info()` | Per-thread state |
| `sched_setaffinity()` | No equivalent | Haiku scheduler handles affinity |
| `prctl()` | No equivalent | — |

### spawn_thread details

```cpp
thread_id spawn_thread(thread_func func, const char *name,
    int32 priority, void *data);
// Thread starts SUSPENDED — must call resume_thread()
```

Priority constants: `B_LOW_PRIORITY` (5), `B_NORMAL_PRIORITY` (10),
`B_DISPLAY_PRIORITY` (15), `B_URGENT_DISPLAY_PRIORITY` (20),
`B_REAL_TIME_PRIORITY` (120).

### load_image details

```cpp
thread_id load_image(int32 argc, const char **argv, const char **environ);
// Process starts SUSPENDED — must call resume_thread()
// Use wait_for_thread() to get exit status
```

## Dynamic Loading

| Linux API | Haiku Equivalent | Notes |
|-----------|-----------------|-------|
| `dlopen()` | `load_add_on()` | dlopen also works (wrapper) |
| `dlclose()` | `unload_add_on()` | — |
| `dlsym()` | `get_image_symbol()` | Need symbol type: B_SYMBOL_TYPE_TEXT (0x2), _DATA (0x1), _ANY (0x5) |
| `dlerror()` | Check status_t return | Native API uses status codes, not strings |
| `dladdr()` | `get_nth_image_info()` | Iterate image symbols |
| `RTLD_LAZY` / `RTLD_NOW` | No equivalent | load_add_on always resolves immediately |

## Shared Memory & IPC

| Linux API | Haiku Equivalent | Notes |
|-----------|-----------------|-------|
| `shmget` / `shmat` / `shmdt` | `create_area()` / `clone_area()` | Areas are named, findable cross-process |
| `mmap(MAP_SHARED)` | `create_area()` | Areas with B_ANY_ADDRESS |
| `sem_init` / `sem_wait` / `sem_post` | `create_sem()` / `acquire_sem()` / `release_sem()` | Named, cross-process capable |
| `msgget` / `msgsnd` / `msgrcv` | `create_port()` / `write_port()` / `read_port()` | Ports carry typed messages with int32 code |
| `pipe()` | `pipe()` | Fully supported |
| `socketpair()` | `socketpair()` | Fully supported |
| `AF_UNIX` | `AF_UNIX` | Fully supported including abstract sockets |
| `futex()` | No direct equiv | Use Haiku semaphores or pthread mutexes |

### Area functions

```cpp
area_id create_area(const char *name, void **startAddress,
    uint32 addressSpec, size_t size, uint32 lock, uint32 protection);
area_id clone_area(const char *name, void **destAddress,
    uint32 addressSpec, uint32 protection, area_id source);
area_id find_area(const char *name);
status_t delete_area(area_id id);
status_t resize_area(area_id id, size_t newSize);
```

Address specs: `B_ANY_ADDRESS`, `B_EXACT_ADDRESS`, `B_BASE_ADDRESS`, `B_CLONE_ADDRESS`.
Lock: `B_NO_LOCK`, `B_LAZY_LOCK`, `B_FULL_LOCK`, `B_CONTIGUOUS`.
Protection: `B_READ_AREA`, `B_WRITE_AREA`, `B_EXECUTE_AREA`, `B_STACK_AREA`.

### Port functions

```cpp
port_id create_port(int32 capacity, const char *name);
ssize_t write_port(port_id port, int32 code, const void *buffer, size_t bufferSize);
ssize_t read_port(port_id port, int32 *code, void *buffer, size_t bufferSize);
status_t close_port(port_id port);
status_t delete_port(port_id port);
```

### Semaphore functions

```cpp
sem_id create_sem(int32 count, const char *name);
status_t acquire_sem(sem_id id);
status_t acquire_sem_etc(sem_id id, int32 count, uint32 flags, bigtime_t timeout);
status_t release_sem(sem_id id);
status_t release_sem_etc(sem_id id, int32 count, uint32 flags);
status_t delete_sem(sem_id id);
```

## Filesystem

| Linux API | Haiku Equivalent | Notes |
|-----------|-----------------|-------|
| `xattr` (getxattr/setxattr) | `BNode::ReadAttr()` / `WriteAttr()` | Native BFS extended attributes; also `fs_read_attr()` C API |
| `/etc/config` | `find_directory(B_USER_SETTINGS_DIRECTORY)` | → /boot/home/config/settings |
| `/usr/lib` | `find_directory(B_SYSTEM_LIB_DIRECTORY)` | → /boot/system/lib |
| `/usr/bin` | `find_directory(B_SYSTEM_BIN_DIRECTORY)` | → /boot/system/bin |
| `/tmp` | `find_directory(B_SYSTEM_TEMP_DIRECTORY)` | → /boot/system/cache/tmp |
| `$HOME` | `find_directory(B_USER_DIRECTORY)` | → /boot/home |
| `/proc/cpuinfo` | `get_system_info()` | Returns system_info struct with CPU count, type, etc. |
| `statvfs()` | `statvfs()` | Works; BFS also has `fs_stat_dev()` |
| `fanotify` | No equivalent | Use BNodeMonitor |
| `statx()` | `stat()` | Standard POSIX stat works |

### find_directory key constants

| Constant | Typical Path |
|----------|-------------|
| B_USER_SETTINGS_DIRECTORY | /boot/home/config/settings |
| B_USER_DIRECTORY | /boot/home |
| B_SYSTEM_DIRECTORY | /boot/system |
| B_SYSTEM_LIB_DIRECTORY | /boot/system/lib |
| B_SYSTEM_BIN_DIRECTORY | /boot/system/bin |
| B_SYSTEM_APPS_DIRECTORY | /boot/system/apps |
| B_SYSTEM_TEMP_DIRECTORY | /boot/system/cache/tmp |
| B_SYSTEM_DATA_DIRECTORY | /boot/system/data |

## Networking

| Linux API | Haiku Equivalent | Notes |
|-----------|-----------------|-------|
| BSD sockets | BSD sockets | Fully compatible |
| `AF_NETLINK` | No equivalent | Route/interface info via ioctl or BNetworkInterface |
| `SO_REUSEPORT` | Not supported | Use SO_REUSEADDR |
| `accept4()` | `accept()` + `fcntl()` | No accept4; set flags after accept |
| `sendmmsg` / `recvmmsg` | No equivalent | Use send/recv in a loop |
| `getifaddrs()` | `getifaddrs()` | Supported |
| `if_nameindex()` | `if_nameindex()` | Supported |

## Signals

| Linux API | Haiku Equivalent | Notes |
|-----------|-----------------|-------|
| `sigaction()` | `sigaction()` | Fully supported |
| `signal()` | `signal()` | Supported but sigaction preferred |
| `SIGRTMIN` / `SIGRTMAX` | Not available | No real-time signals |
| `signalfd()` | No equivalent | Use signal handler + pipe/port |
| `sigtimedwait()` | `sigtimedwait()` | Supported |

## System Information

| Linux API | Haiku Equivalent | Notes |
|-----------|-----------------|-------|
| `/proc/meminfo` | `get_system_info()` → `system_info.max_pages`, `used_pages` | — |
| `/proc/cpuinfo` | `get_system_info()` → `system_info.cpu_count`, `cpu_type` | — |
| `/proc/uptime` | `system_time()` | Returns microseconds since boot |
| `sysconf()` | `sysconf()` | Most _SC_* constants supported |
| `uname()` | `uname()` | Returns "Haiku" as sysname |
| `getrlimit()` / `setrlimit()` | Partially supported | Some limits not implemented |

## HaikuPorts Recipe Quick Reference

### Minimum viable recipe

```
SUMMARY="One line description"
DESCRIPTION="Detailed description."
HOMEPAGE="https://example.com"
COPYRIGHT="2024 Author Name"
LICENSE="MIT"
REVISION="1"
SOURCE_URI="https://example.com/foo-$portVersion.tar.gz"
CHECKSUM_SHA256="<hash>"
ARCHITECTURES="all !x86_gcc2"
PROVIDES="
    foo = $portVersion
    cmd:foo = $portVersion
    "
REQUIRES="
    haiku
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

### Recipe variables

| Variable | Meaning |
|----------|---------|
| `$portVersion` | Version from filename (e.g., 1.2.3) |
| `$portName` | Package name |
| `$sourceDir` | Unpacked source tree |
| `$prefix` | Installation prefix |
| `$binDir` | Binary directory |
| `$libDir` | Runtime library directory |
| `$developLibDir` | Development library directory |
| `$includeDir` | Header directory |
| `$dataDir` | Shared data directory |
| `$manDir` | Man page directory |
| `$docDir` | Documentation directory |
| `$settingsDir` | Settings directory |
| `$jobArgs` | Parallel build flags (e.g., -j4) |

### Recipe helper functions

| Function | Purpose |
|----------|---------|
| `runConfigure ./configure [args]` | Invoke configure with Haiku-correct paths |
| `packageEntries <suffix> <files>` | Move files into a sub-package |
| `prepareInstalledDevelLibs <name>` | Split lib vs devel files |
| `fixPkgconfig` | Fix .pc file install paths |
| `addAppDeskbarSymlink <path> [name]` | Add app to Deskbar menu |

### Architecture markers

| Marker | Meaning |
|--------|---------|
| `x86_gcc2` | 32-bit BeOS ABI compatible |
| `x86` | 32-bit modern GCC |
| `x86_64` | 64-bit |
| `!arch` | Broken on this arch |
| `?arch` | Untested on this arch |
| `all` | All architectures |
| `any` | Architecture-independent |
