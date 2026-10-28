# HaikuPorts Recipe Template — Fully Annotated

This is a complete, annotated HaikuPorts recipe showing every common field and
pattern. Use as a reference when writing new recipes.

## Complete Recipe

```bash
# ============================================================================
# METADATA — required fields
# ============================================================================

# One-line summary shown in pkgman/HaikuDepot search results.
SUMMARY="A short description of what this package does"

# Multi-line description. Use backslash line continuations.
# Newlines within the string are preserved in package metadata.
DESCRIPTION="A longer description of the software. This is shown in \
HaikuDepot and package info output. It can span multiple lines using \
backslash continuations.

Features include:
\- Feature one
\- Feature two
\- Feature three"

HOMEPAGE="https://upstream-project.example.com/"

# Copyright holder(s). Multiple years/ranges OK.
COPYRIGHT="2020-2024 Author Name
	2018 Other Contributor"

# SPDX license identifier(s). Multiple licenses separated by newlines.
# Common values: MIT, GNU GPL v2, GNU GPL v3, GNU LGPL v2.1, BSD (2-clause),
#                BSD (3-clause), Apache v2, ISC, Artistic, Zlib, Boost v1
LICENSE="MIT"

# Bump this when changing the recipe without changing upstream version.
# Reset to "1" when upstream version changes.
REVISION="1"

# ============================================================================
# SOURCES — where to download
# ============================================================================

# $portVersion is auto-extracted from the recipe filename.
# For filename my-package-1.2.3.recipe → $portVersion = 1.2.3
SOURCE_URI="https://github.com/example/project/archive/v$portVersion.tar.gz"

# SHA-256 of the downloaded archive. Generate with:
#   sha256sum <downloaded-file>
CHECKSUM_SHA256="0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

# Directory name inside the archive (if different from default).
# Default is auto-detected. Set this only if extraction creates an
# unexpected directory name.
SOURCE_DIR="project-$portVersion"

# Additional source archives (numbered 2, 3, ...):
# SOURCE_URI_2="https://example.com/extra-data.tar.gz"
# CHECKSUM_SHA256_2="..."
# SOURCE_DIR_2="extra-data"

# ============================================================================
# PATCHES — auto-applied before BUILD()
# ============================================================================

# Place patchfiles in a patches/ directory alongside the recipe:
#   <category>/<portname>/patches/<portname>-<version>.patchset
#
# A .patchset is a concatenation of git-format patches (git format-patch output).
# They are applied with `git am` inside the source directory.
#
# You can also use individual .patch files:
#   patches/<portname>-<version>-fix-haiku.patch
#
# PATCHES is auto-populated from the patches/ directory. You can also set it
# explicitly:
# PATCHES="mypackage-$portVersion.patchset"

# ============================================================================
# ARCHITECTURE
# ============================================================================

# Which architectures this package supports.
# "all" = all architectures.  "any" = architecture-independent (data, docs).
# Exclude specific archs with !:
#   "all !x86_gcc2"  — works everywhere except the legacy gcc2 ABI
#   "x86_gcc2 x86_64" — only these two
ARCHITECTURES="all !x86_gcc2"

# Build as a secondary architecture too.
# On x86_64 Haiku, "x86" builds the x86_gcc2-compatible 32-bit variant.
# Secondary arch packages get $secondaryArchSuffix appended to names.
SECONDARY_ARCHITECTURES="x86"

# ============================================================================
# SECONDARY ARCHITECTURE HELPERS
# ============================================================================

# These variables adapt paths and suffixes based on which architecture
# variant is currently being built.

commandSuffix=$secondaryArchSuffix
commandBinDir=$binDir

# On the secondary (gcc2-compat) architecture, commands go to $prefix/bin
# instead of $binDir to avoid conflicts with the primary arch version.
if [ "$targetArchitecture" = x86_gcc2 ]; then
	commandSuffix=
	commandBinDir=$prefix/bin
fi

# ============================================================================
# PROVIDES — what this package gives the system
# ============================================================================

# Format:  <entity_type>:<name>$suffix = <version> [compat >= <compat_version>]
#
# Entity types:
#   (bare name)  — the package itself
#   cmd:         — a command-line executable
#   lib:         — a shared library (use the SONAME, e.g. lib:libfoo = 1.2.3)
#   devel:       — development files (headers + .a/.so symlinks)
#   app:         — GUI application
#   addon:       — add-on/plugin
#
# compat >= X means this package is backwards-compatible with version X.

PROVIDES="
	mypackage$secondaryArchSuffix = $portVersion
	cmd:mytool$commandSuffix = $portVersion compat >= 1
	lib:libmylib$secondaryArchSuffix = 2.1.0 compat >= 2
"

# For a -devel sub-package, add a PROVIDES block in the
# corresponding _devel package definition (see sub-packages below).

# ============================================================================
# REQUIRES — runtime dependencies
# ============================================================================

REQUIRES="
	haiku$secondaryArchSuffix
	lib:libz$secondaryArchSuffix
	lib:libssl$secondaryArchSuffix >= 3
	lib:libncurses$secondaryArchSuffix
"

# ============================================================================
# BUILD DEPENDENCIES
# ============================================================================

# BUILD_REQUIRES are needed at compile time (headers, static libs).
BUILD_REQUIRES="
	haiku${secondaryArchSuffix}_devel
	devel:libz$secondaryArchSuffix
	devel:libssl$secondaryArchSuffix >= 3
	devel:libncurses$secondaryArchSuffix
"

# BUILD_PREREQUIRES are tools needed to run the build (compilers, make, etc.).
BUILD_PREREQUIRES="
	cmd:cmake
	cmd:gcc$secondaryArchSuffix
	cmd:ld$secondaryArchSuffix
	cmd:make
	cmd:pkg_config$secondaryArchSuffix
"

# Note: cmd:pkg_config (underscore) not cmd:pkg-config (hyphen).
# HaikuPorts normalizes hyphens to underscores in command names.

# ============================================================================
# SUB-PACKAGES (optional)
# ============================================================================

# Define additional packages built from the same recipe.
# Common pattern: separate -devel package for headers and static libs.

# PROVIDES_devel="
# 	mypackage${secondaryArchSuffix}_devel = $portVersion
# 	devel:libmylib$secondaryArchSuffix = 2.1.0 compat >= 2
# "
# REQUIRES_devel="
# 	mypackage$secondaryArchSuffix == $portVersion base
# "

# ============================================================================
# BUILD() — compile the software
# ============================================================================

BUILD()
{
	# runConfigure wraps ./configure with Haiku-correct paths:
	#   --prefix, --bindir, --libdir, --includedir, --datadir, etc.
	#
	# Flags:
	#   --omit-dirs <dir>  — don't pass --<dir>dir to configure
	#   Extra args after ./configure are passed through.

	runConfigure --omit-dirs binDir ./configure \
		--bindir=$commandBinDir \
		--enable-shared \
		--disable-static

	# $jobArgs expands to -jN for parallel builds.
	make $jobArgs
}

# Alternative: cmake-based build
# BUILD()
# {
# 	cmake -B build -S . \
# 		-DCMAKE_BUILD_TYPE=Release \
# 		-DCMAKE_INSTALL_PREFIX=$prefix \
# 		-DCMAKE_INSTALL_BINDIR=$commandBinDir \
# 		-DCMAKE_INSTALL_LIBDIR=$libDir \
# 		-DCMAKE_INSTALL_INCLUDEDIR=$includeDir
# 	make -C build $jobArgs
# }

# Alternative: meson-based build
# BUILD()
# {
# 	meson setup build --prefix=$prefix --libdir=$libDir \
# 		--bindir=$commandBinDir --buildtype=release
# 	meson compile -C build
# }

# ============================================================================
# INSTALL() — install into the package staging area
# ============================================================================

INSTALL()
{
	make install

	# If the build installs to wrong locations, move things:
	# mkdir -p $binDir
	# cp build/mytool $binDir/

	# Install documentation
	# mkdir -p $docDir
	# cp README.md $docDir/

	# For -devel sub-packages, call packageEntries to move dev files
	# into the sub-package:
	# prepareInstalledDevelLibs libmylib
	# fixPkgconfig
	# packageEntries devel \
	# 	$developDir
}

# Alternative: cmake install
# INSTALL()
# {
# 	make -C build install
# 	prepareInstalledDevelLibs libmylib
# 	fixPkgconfig
# 	packageEntries devel $developDir
# }

# ============================================================================
# TEST() — optional, run test suite
# ============================================================================

# TEST()
# {
# 	make check
# }
```

## Directory Layout Reference

Standard variables available in BUILD() and INSTALL():

| Variable | Typical Value (primary arch) |
|----------|------------------------------|
| `$prefix` | `/boot/system` |
| `$binDir` | `/boot/system/bin` |
| `$libDir` | `/boot/system/lib` |
| `$includeDir` | `/boot/system/develop/headers` |
| `$dataDir` | `/boot/system/data` |
| `$docDir` | `/boot/system/documentation/packages/<name>` |
| `$manDir` | `/boot/system/documentation/man` |
| `$infoDir` | `/boot/system/documentation/info` |
| `$settingsDir` | `/boot/system/settings` |
| `$developDir` | `/boot/system/develop` |
| `$developLibDir` | `/boot/system/develop/lib` |
| `$addOnsDir` | `/boot/system/add-ons` |
| `$appsDir` | `/boot/system/apps` |
| `$preferencesDir` | `/boot/system/preferences` |

With `$secondaryArchSuffix` (e.g., `_x86`), lib/develop paths get the arch
suffix: `/boot/system/lib/x86/`, `/boot/system/develop/lib/x86/`.

## Helper Functions

| Function | Purpose |
|----------|---------|
| `runConfigure` | Wraps configure with correct Haiku paths |
| `prepareInstalledDevelLibs` | Move .so symlinks and .a into develop tree |
| `fixPkgconfig` | Patch .pc files to use correct Haiku paths |
| `packageEntries <sub> <dirs...>` | Move files into a sub-package |
| `install -m 755 -d <dir>` | Create directory with permissions |

## Versioning Convention

Recipe filename determines `$portVersion`:
```
app-editors/nano/nano-9.1.recipe     → $portVersion = 9.1
dev-libs/openssl/openssl-3.3.2.recipe → $portVersion = 3.3.2
```

Bump `REVISION` (not the filename) for recipe-only changes.
Change the filename when packaging a new upstream release.
