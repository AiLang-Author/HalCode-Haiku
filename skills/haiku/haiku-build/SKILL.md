---
name: haiku-build
description: Haiku OS build system — Jam/BJam rules, Jamfiles, HaikuPorts recipe authoring, pkgman package management, .hpkg packages, cross-compilation from Linux. Load when building Haiku applications, writing Jamfiles, creating or editing HaikuPorts recipes, packaging software for Haiku, or working with pkgman/HaikuDepot. Use whenever Haiku build, Jam, BJam, Jamfile, HaikuPorts, recipe, .hpkg, pkgman, findpaths, or Haiku cross-compile is mentioned — even if the user just says "build" or "compile" in a Haiku context.
---

# Haiku Build System

Haiku uses **Jam** (specifically a Haiku-patched fork) as its build system, both for building
Haiku itself and for building applications that ship with the OS. Third-party software is
packaged via **HaikuPorts** recipes. Installed packages use the `.hpkg` format managed by
`pkgman` (CLI) or HaikuDepot (GUI).

## Jam Basics

Jam is a make-replacement that uses **rules** (functions) and **actions** (shell commands).

### Syntax Fundamentals

```jam
# Variables — always lists of strings, referenced with $(VAR)
MY_SRCS = main.cpp utils.cpp ;
CCFLAGS += -Wall -O2 ;

# Rules — invoked as:  RuleName arg1 : arg2 : arg3 ;
# Semicolons and spaces around colons are MANDATORY.
Application MyApp : $(MY_SRCS) : be $(HAIKU_LOCALE_LIBS) ;

# Conditionals
if $(TARGET_ARCH) = x86_64 {
    CCFLAGS += -m64 ;
}

# Loops
for src in $(MY_SRCS) {
    Echo $(src) ;
}
```

**Critical syntax rules:**
- Every statement ends with ` ;` (space before semicolon)
- Arguments separated by ` : ` (spaces around colon)
- Variables are **always lists** — `VAR = foo ;` is a one-element list
- `$(VAR)` expands the list; `$(VAR[1])` is the first element
- `on TARGET VAR = value ;` sets VAR scoped to a specific target
- `local VAR = value ;` scopes to the enclosing `{ }` block

### Built-in Jam Features

| Feature | Syntax |
|---------|--------|
| File exists test | `if $(VAR:E) { }` |
| Glob files | `GLOB dir : pattern` |
| Include another Jamfile | `include file ;` or `SubInclude ...` |
| Set search path | `SEARCH on target = dirs ;` |
| Set output dir | `LOCATE on target = dir ;` |
| Depend | `Depends target : sources ;` |

---

## Haiku-Specific Jam Rules

These rules are defined in `build/jam/` in the Haiku source tree. They are available when
building inside the Haiku tree or when using the Haiku development headers/tools.

### Application — Build an executable

```jam
Application MyApp :
    main.cpp
    Window.cpp
    View.cpp
    : be tracker translation localestub shared
    [ TargetLibsupc++ ] [ TargetLibstdc++ ]
    : MyApp.rdef
;
```

**Arguments:** `Application name : sources : libraries : resources ;`

- **name** — output binary name
- **sources** — C/C++ source files
- **libraries** — link libraries (`be` = libbe, `tracker` = libtracker, etc.)
- **resources** — `.rdef` files compiled to binary resources and merged into the executable

Common link libraries:
| Library | Provides |
|---------|----------|
| `be` | libbe — App Kit, Interface Kit, Storage Kit, Support Kit |
| `tracker` | libtracker — file manager integration |
| `translation` | Translation Kit — image/media format conversion |
| `localestub` | Locale Kit stub for catalog string lookups |
| `shared` | libshared — shared utility classes |
| `network` | Network Kit — sockets, HTTP |
| `media` | Media Kit — audio/video |
| `game` | Game Kit — BWindowScreen, direct access |
| `mail` | Mail Kit |
| `device` | Device Kit |
| `textencoding` | Text encoding conversions |

### SharedLibrary — Build a .so

```jam
SharedLibrary libmylib.so :
    mylib.cpp
    : be
;
```

### StaticLibrary — Build a .a

```jam
StaticLibrary libmyhelper.a :
    helper.cpp utils.cpp
;
```

### Preference — Build a preflet

```jam
Preference MyPreflet :
    PrefletWindow.cpp
    PrefletView.cpp
    : be localestub
    : MyPreflet.rdef
;
```

Installs to `/boot/system/preferences/`.

### AddResources — Attach resources without .rdef in the rule

```jam
AddResources MyApp : MyApp.rdef ;
```

### DoCatalogs — Localization support

```jam
DoCatalogs MyApp :
    x-vnd.MyCompany-MyApp
    :
    MainWindow.cpp
    SettingsView.cpp
    : en.catalog
;
```

Extracts translatable strings from source files for the Locale Kit.

### SubDir / SubInclude — Source tree navigation

```jam
# At the top of every Jamfile — declares this directory's position
SubDir HAIKU_TOP src apps myapp ;

# Include a subdirectory's Jamfile
SubInclude HAIKU_TOP src apps myapp plugins ;
```

### UseHeaders / UsePrivateHeaders

```jam
# Add include search paths
UseHeaders [ FDirName $(HAIKU_TOP) src kits tracker ] ;

# Use Haiku private headers (not part of public API)
UsePrivateHeaders libroot shared system ;
UsePrivateHeaders interface ;
```

### MergeObject — Combine objects for later linking

```jam
MergeObject <libbe!$(architecture)>interface_kit.o :
    BView.cpp BWindow.cpp BControl.cpp
    : $(TARGET_SHARED_LIBS)
;
```

Used when building Haiku's own kits; rarely needed for third-party apps.

---

## Building a Haiku Application (Standalone)

For apps **outside** the Haiku source tree, use a simplified Jamfile or a Makefile
with Haiku's standard compiler and linker flags.

### Makefile approach (simpler for ported software)

```makefile
APP = MyApp
SRCS = main.cpp Window.cpp View.cpp
LIBS = -lbe -ltranslation -llocalestub

$(APP): $(SRCS)
	g++ -o $@ $^ $(LIBS)
	rc -o $(APP).rsrc $(APP).rdef
	xres -o $@ $(APP).rsrc
	mimeset -f $@
```

Key commands:
- `rc` — compile `.rdef` to binary `.rsrc`
- `xres` — merge resources into executable
- `mimeset` — set MIME type attributes on the file

### cmake (increasingly common)

Haiku ships cmake. Many ports use it. Link against `be`, `tracker`, etc. as normal
shared libraries.

---

## Resource Files (.rdef)

`.rdef` is a text format compiled by `rc` into binary resources.

```rdef
resource app_signature "application/x-vnd.MyCompany-MyApp";
resource app_name_catalog_entry "x-vnd.MyCompany-MyApp:System name:MyApp";

resource app_version {
    major  = 1,
    middle = 0,
    minor  = 0,
    variety = B_APPV_FINAL,
    internal = 0,
    short_info = "MyApp",
    long_info  = "MyApp 1.0 — a sample application"
};

resource app_flags B_SINGLE_LAUNCH;

resource vector_icon {
    $"6E636966..."
};
```

---

## HaikuPorts Recipe System

HaikuPorts is the ports tree for Haiku. Recipes are shell-like files with a
structured header and bash functions.

> See `references/recipe-template.md` for a fully annotated recipe.

### Recipe file naming

```
<portname>-<version>.recipe
```
Lives in `<category>/<portname>/` inside the haikuports tree.
Categories mirror Gentoo: `app-editors`, `dev-libs`, `media-libs`, etc.

### Minimal recipe skeleton

```bash
SUMMARY="One-line description"
DESCRIPTION="Multi-line description"
HOMEPAGE="https://example.com"
COPYRIGHT="2024 Author Name"
LICENSE="MIT"
REVISION="1"
SOURCE_URI="https://example.com/pkg-$portVersion.tar.gz"
CHECKSUM_SHA256="abc123..."

ARCHITECTURES="all !x86_gcc2"
SECONDARY_ARCHITECTURES="x86"

PROVIDES="
    cmd:mycommand = $portVersion
"
REQUIRES="
    haiku
"
BUILD_REQUIRES="
    haiku_devel
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

### Key recipe variables

| Variable | Purpose |
|----------|---------|
| `$portVersion` | Auto-set from filename |
| `$jobArgs` | Parallel make flag (`-jN`) |
| `$secondaryArchSuffix` | `_x86` on secondary arch, empty on primary |
| `$prefix` | Installation prefix (from `runConfigure`) |
| `$binDir`, `$libDir`, `$includeDir`, `$dataDir` | Standard dirs |
| `$commandBinDir` | Where commands go (arch-aware) |
| `$developDir`, `$developLibDir` | Development files |
| `$docDir`, `$manDir`, `$infoDir` | Documentation |

### runConfigure

Wrapper that calls `./configure` with correct `--prefix`, `--bindir`, `--libdir`,
etc. for Haiku's directory layout.

```bash
runConfigure ./configure                    # basic
runConfigure --omit-dirs binDir ./configure --bindir=$commandBinDir  # override binDir
runConfigure ./configure --enable-shared    # pass extra flags
```

### Architecture handling

```bash
ARCHITECTURES="all !x86_gcc2"           # works on all EXCEPT gcc2 ABI
SECONDARY_ARCHITECTURES="x86"           # also build as secondary arch

# In PROVIDES/REQUIRES, append $secondaryArchSuffix:
PROVIDES="
    mylib$secondaryArchSuffix = $portVersion
    lib:libmything$secondaryArchSuffix = $portVersion
    devel:libmything$secondaryArchSuffix = $portVersion
"
```

### Patching

Place patchfiles in `<portname>/patches/` alongside the recipe. They are applied
automatically before `BUILD()` runs. Name them `<portname>-<version>.patchset`.

---

## Package Management

### pkgman (CLI)

```bash
pkgman install nano                  # install a package
pkgman uninstall nano                # remove
pkgman search sdl2                   # search by name
pkgman update                        # update all packages
pkgman full-sync                     # sync + upgrade base system
pkgman list-repos                    # show configured repos
pkgman add-repo <url>                # add a repository
pkgman drop-repo <name>              # remove a repository
```

### HaikuDepot (GUI)

Full graphical package manager with ratings, screenshots, categories.
Backed by the same package repos as pkgman.

### .hpkg format

Packages are self-contained compressed archives. When activated, their contents
appear at `/boot/system/` via packagefs (a virtual filesystem). Packages are
never "extracted" — packagefs mounts them read-only.

Key properties:
- Atomic activation/deactivation (no partial installs)
- Stored in `/boot/system/packages/`
- Package attributes describe provides/requires for dependency resolution
- `package create/extract/list/info` CLI tools for manual inspection

---

## findpaths — Locating System Directories

Haiku does NOT use `/usr`, `/etc`, `/var`. Use `findpaths` to locate directories:

```bash
findpaths -e B_FIND_PATH_BIN_DIRECTORY          # /boot/system/bin etc.
findpaths -e B_FIND_PATH_LIB_DIRECTORY          # /boot/system/lib etc.
findpaths -e B_FIND_PATH_HEADERS_DIRECTORY       # /boot/system/develop/headers
findpaths -e B_FIND_PATH_DATA_DIRECTORY          # /boot/system/data
findpaths -e B_FIND_PATH_SETTINGS_DIRECTORY      # /boot/system/settings
findpaths -e B_FIND_PATH_APPS_DIRECTORY          # /boot/system/apps
findpaths -e B_FIND_PATH_PREFERENCES_DIRECTORY   # /boot/system/preferences
```

In C++, use `BPathFinder` or `find_paths()` from `FindDirectory.h`.

---

## Cross-Compilation from Linux

Building Haiku or Haiku software from a Linux host:

```bash
# 1. Clone both repos
git clone https://review.haiku-os.org/haiku
git clone https://review.haiku-os.org/buildtools

# 2. Create build directory and configure
mkdir generated.x86_64 && cd generated.x86_64
../configure --cross-tools-source ../../buildtools --build-cross-tools x86_64

# 3. Build an image
jam -q -j$(nproc) @nightly-anyboot    # bootable ISO
jam -q -j$(nproc) @nightly-raw        # raw disk image for VMs
```

The configure step builds a cross-compiler targeting Haiku. All subsequent `jam`
invocations use this cross-toolchain automatically.

**jam flags:**
- `-q` — quit on first error
- `-jN` — parallel jobs
- `@profile` — build profile (nightly-anyboot, nightly-raw, etc.)
