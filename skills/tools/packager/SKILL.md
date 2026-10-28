---
name: packager
description: AILang project packaging tool. Use when asked to scan, analyze, build, or package AILang projects.
---

# Packager Tool

## When to Load
- User asks to scan or analyze an AILang project
- User asks about dependencies or build order
- User asks to create a package, manifest, or install script
- User asks to build or compile an AILang project
- User asks to package or archive an AILang project

## Operations

### Scan a project
```
Packager op=scan dir=/path/to/project
```
Lists all files with type classification (SOURCE, BINARY, SCRIPT, CONFIG, DOCS).
Identifies entry points (files containing SubRoutine.Main).
Returns file count, type breakdown, entry point count, directory count, total size.

### Dependency graph
```
Packager op=graph dir=/path/to/project
```
Parses import statements in all .ailang files.
Builds dependency graph, runs topological sort.
Detects circular dependencies.
Returns: dependency tree per file, topological build order, cycle status.

### Initialize package
```
Packager op=init dir=/path/to/project
```
Scans project, creates `package.json` manifest from scan results.
Generates `install.sh` script.
Returns confirmation and generated file paths.

### Project info
```
Packager op=info dir=/path/to/project
```
Loads existing `package.json` if present.
Scans project and returns package metadata plus file summary.

### Build all targets
```
Packager op=build dir=/path/to/project
```
Scans, parses imports, builds dependency graph, compiles all entry-point .ailang files via ailang.x.
Reports success/failure per target with a summary.

### Pack archive
```
Packager op=pack dir=/path/to/project output=/path/to/output.tar.gz
```
Creates distributable tar.gz archive containing source, binaries, and install.sh.
`output` is optional (defaults to `<project_name>.tar.gz` in the project dir).

## Output Format

All operations return plain text summaries. Scan and info include counts and file listings.
Graph returns indented dependency trees and numbered build order.
Build returns per-target pass/fail lines.

## Typical Workflows

1. **Analyze a project**: `op=scan` then `op=graph` to understand structure and dependencies.
2. **Prepare for distribution**: `op=init` to create manifest, `op=build` to compile, `op=pack` to archive.
3. **Check build order**: `op=graph` shows topological sort and cycle detection.
