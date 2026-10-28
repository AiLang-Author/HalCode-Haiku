#!/usr/bin/env bash
# build.sh — rebuild HalCode9000 and its cc_tools.
#
# Usage:
#   ./build.sh                     # rebuild everything
#   ./build.sh --no-tools          # rebuild just the main binary (fast iteration)
#   ./build.sh --tools-only        # rebuild only the cc_*_ipc tools
#   ./build.sh --quiet             # suppress per-file [ok] output
#   ./build.sh --no-copy           # build to /tmp only, don't touch project root
#   ./build.sh --self-update       # rebuild, install, gracefully restart the GTK app
#   ./build.sh --self-update --dry-run  # show the stop/restart plan, change nothing
#
# Behavior:
#   - All ailang.x compiles go to /tmp first.
#   - Fails fast if any compile fails (the rest are skipped).
#   - On success, atomically copies all built binaries to project root.
#   - "Atomic" here means: either every binary updates, or none does.
#     If you ctrl-C mid-copy, your project-root binaries stay coherent
#     because we copy to *.new files first, then rename.
#
# Copyright 2026 Sean Collins, 2 Paws Machine and Engineering. MIT.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---- arg parsing ------------------------------------------------------------
BUILD_MAIN=1
BUILD_TOOLS=1
QUIET=0
COPY=1
SELF_UPDATE=0
DRY_RUN=0

for arg in "$@"; do
    case "$arg" in
        --no-tools)    BUILD_TOOLS=0 ;;
        --tools-only)  BUILD_MAIN=0 ;;
        --quiet|-q)    QUIET=1 ;;
        --no-copy)     COPY=0 ;;
        --self-update) SELF_UPDATE=1; COPY=1 ;;
        --dry-run)     DRY_RUN=1 ;;
        --help|-h)
            sed -n '2,11p' "$0" | sed 's/^# \?//'
            exit 0
            ;;
        *)
            echo "build.sh: unknown arg: $arg (try --help)" >&2
            exit 2
            ;;
    esac
done

# ---- preflight --------------------------------------------------------------
AILANG="$(command -v ailang.x 2>/dev/null || true)"
if [[ -z "$AILANG" ]]; then
    echo "build.sh: ailang.x not found in PATH — run install_compiler.sh first" >&2
    exit 1
fi

# The AILang tree root is where local imports (Applications.<App>.*,
# Packager.Packager.*) resolve. Derive it from the compiler's real location.
AILANG_ROOT="$(cd "$(dirname "$(readlink -f "$AILANG")")" && pwd)"
cd "$AILANG_ROOT"

# Tool list: bare names, expanded both for source and binary
TOOLS=(read head ls write bash webfetch edit find grep git)

# ---- build phase: everything goes to /tmp first ----------------------------
log() { [[ $QUIET -eq 1 ]] || echo "$@"; }

# ---- graceful restart (--self-update) --------------------------------------
# Stops the running GTK app (desk + shell + their --host/--agent children) and
# leaves the long-lived --mcp servers untouched (they run from the other tree).
stop_app() {
    local pid i
    if [[ $DRY_RUN -eq 1 ]]; then
        echo "  [dry-run] would stop: halcode_desk.x, halcode_shell_haiku, HalCode9000.x --host/--agent"
        return 0
    fi
    echo "  Stopping running HalCode app..."
    pkill -x halcode_desk.x 2>/dev/null || true
    pkill -x halcode_shell_h 2>/dev/null || true
    for pid in /tmp/halcode_desk.pid /tmp/halcode_gtk.pid; do
        [[ -f "$pid" ]] && kill "$(cat "$pid" 2>/dev/null)" 2>/dev/null || true
    done
    # Desk-spawned agent loop + sub-agents (pattern never matches --mcp).
    pgrep -f 'HalCode9000\.x (--host|--agent)' 2>/dev/null | xargs -r kill 2>/dev/null || true

    for i in 1 2 3 4 5; do
        if ! pgrep -x halcode_desk.x >/dev/null 2>&1 \
           && ! pgrep -x halcode_shell_h >/dev/null 2>&1 \
           && ! pgrep -f 'HalCode9000\.x (--host|--agent)' >/dev/null 2>&1; then
            echo "  Stopped."
            return 0
        fi
        sleep 1
    done

    echo "  Forcing remaining app processes..." >&2
    pkill -9 -x halcode_desk.x 2>/dev/null || true
    pkill -9 -x halcode_shell_h 2>/dev/null || true
    pgrep -f 'HalCode9000\.x (--host|--agent)' 2>/dev/null | xargs -r kill -9 2>/dev/null || true
    sleep 1
}

start_app() {
    local launcher="$ROOT/scripts/launch_halcode.sh"
    if [[ $DRY_RUN -eq 1 ]]; then
        echo "  [dry-run] would relaunch: $launcher"
        return 0
    fi
    if [[ ! -x "$launcher" ]]; then
        echo "  Note: no launcher at $launcher — start with: halcode" >&2
        return 1
    fi
    if [[ -z "${DISPLAY:-}" ]]; then
        echo "  Note: no DISPLAY — binaries updated; start the app when ready (halcode)." >&2
        return 1
    fi
    echo "  Relaunching HalCode GTK..."
    nohup "$launcher" >/dev/null 2>&1 &
    disown 2>/dev/null || true
}

build_one() {
    local src="$1"
    local out="$2"
    local label="$3"
    local logf="/tmp/build_${label}.log"

    if $AILANG "$src" "$out" >"$logf" 2>&1; then
        log "  [ok]  $label"
        return 0
    fi

    echo "  [FAIL] $label  (see $logf)" >&2
    # Surface the first real error line; AILang produces a lot of progress noise.
    grep -iE "ERROR|Unknown|FATAL|Failed" "$logf" \
        | grep -vE "^\[POOL|^\[LOAD|^\[STORE|JParse\.error|XERROR|^\[FUNCDEF|OPT-TRY|ARITH |^\[IO\]|^\[FILE\]" \
        | head -3 >&2 || true
    return 1
}

build_app() {
    local app_dir="$1"     # e.g. Applications/ClaudeCode
    local main_src="$2"    # e.g. Applications/ClaudeCode/ClaudeCode.ailang
    local main_bin="$3"    # e.g. ClaudeCode.x
    local tools_dir="$4"   # e.g. Applications/ClaudeCode/cc_tools
    local tmp_prefix="$5"  # e.g. cc  (produces /tmp/cc_bash_ipc.x)

    local install_dir="$app_dir"

    if [[ $BUILD_TOOLS -eq 1 ]]; then
        log "Building ${app_dir} cc_tools..."
        local t local_tools=("${TOOLS[@]}")
        for t in "${local_tools[@]}"; do
            build_one "${tools_dir}/cc_${t}_ipc.ailang" \
                      "/tmp/${tmp_prefix}_cc_${t}_ipc.x" \
                      "${tmp_prefix}_cc_${t}_ipc"
        done
        if [[ -f "${tools_dir}/cc_relmem_ipc.ailang" ]]; then
            build_one "${tools_dir}/cc_relmem_ipc.ailang" \
                      "/tmp/${tmp_prefix}_cc_relmem_ipc.x" \
                      "${tmp_prefix}_cc_relmem_ipc"
            local_tools+=(relmem)
        fi
        if [[ -f "${tools_dir}/cc_pgmem_ipc.ailang" ]]; then
            build_one "${tools_dir}/cc_pgmem_ipc.ailang" \
                      "/tmp/${tmp_prefix}_cc_pgmem_ipc.x" \
                      "${tmp_prefix}_cc_pgmem_ipc"
            local_tools+=(pgmem)
        fi
    if [[ -f "${tools_dir}/cc_agent_ipc.ailang" ]]; then
        build_one "${tools_dir}/cc_agent_ipc.ailang" \
                  "/tmp/${tmp_prefix}_cc_agent_ipc.x" \
                  "${tmp_prefix}_cc_agent_ipc"
        local_tools+=(agent)
    fi
    if [[ -f "${tools_dir}/cc_mcp_ipc.ailang" ]] && [[ -s "${tools_dir}/cc_mcp_ipc.ailang" ]]; then
        build_one "${tools_dir}/cc_mcp_ipc.ailang" \
                  "/tmp/${tmp_prefix}_cc_mcp_ipc.x" \
                  "${tmp_prefix}_cc_mcp_ipc"
        local_tools+=(mcp)
    fi
    for _opt in stat wc du diff olympus sleep skills ailang ailang_lsp packager vision undo; do
        if [[ -f "${tools_dir}/cc_${_opt}_ipc.ailang" ]]; then
            build_one "${tools_dir}/cc_${_opt}_ipc.ailang" \
                      "/tmp/${tmp_prefix}_cc_${_opt}_ipc.x" \
                      "${tmp_prefix}_cc_${_opt}_ipc"
            local_tools+=($_opt)
        fi
    done
        _BUILT_TOOLS=("${local_tools[@]}")
    fi

    if [[ $BUILD_MAIN -eq 1 ]]; then
        log "Building ${main_bin}..."
        build_one "$main_src" "/tmp/${main_bin}" "${main_bin%.x}"
    fi

    if [[ $COPY -eq 1 ]]; then
        if [[ $DRY_RUN -eq 1 ]]; then
            log "Dry-run: would install to $install_dir"
        else
            log "Installing to $install_dir..."
        fi
        local busy=()
        local t
        for t in "${_BUILT_TOOLS[@]}"; do
            local bin="${install_dir}/cc_${t}_ipc.x"
            if [[ -x "$bin" ]] && fuser "$bin" &>/dev/null; then
                busy+=("cc_${t}_ipc.x")
            fi
        done
        local mbin="${install_dir}/${main_bin}"
        if [[ $BUILD_MAIN -eq 1 ]] && [[ -x "$mbin" ]] && fuser "$mbin" &>/dev/null; then
            busy+=("$main_bin")
        fi
        if [[ ${#busy[@]} -gt 0 ]]; then
            if [[ $SELF_UPDATE -eq 1 ]]; then
                echo "" >&2
                echo "build.sh: --self-update: stopping running app to swap binaries..." >&2
                printf '  busy: %s\n' "${busy[@]}" >&2
                APP_RUNNING=1
                stop_app
            else
                echo "" >&2
                echo "build.sh: cannot install — these binaries are currently running:" >&2
                printf '  %s\n' "${busy[@]}" >&2
                echo "Quit the app, then re-run build.sh (or use --self-update)." >&2
                echo "(All builds succeeded; rerun with --no-copy to skip install.)" >&2
                exit 3
            fi
        fi

        if [[ $DRY_RUN -eq 1 ]]; then
            log "Dry-run: skipping binary install."
        else
            if [[ $BUILD_TOOLS -eq 1 ]]; then
                for t in "${_BUILT_TOOLS[@]}"; do
                    cp "/tmp/${tmp_prefix}_cc_${t}_ipc.x" "${install_dir}/cc_${t}_ipc.x.new"
                    mv "${install_dir}/cc_${t}_ipc.x.new" "${install_dir}/cc_${t}_ipc.x"
                done
            fi
            if [[ $BUILD_MAIN -eq 1 ]]; then
                cp "/tmp/${main_bin}" "${install_dir}/${main_bin}.new"
                mv "${install_dir}/${main_bin}.new" "${install_dir}/${main_bin}"
            fi
        fi
    fi
}

_BUILT_TOOLS=()
APP_RUNNING=0
log "build.sh: starting"

build_app "$ROOT" \
          "$ROOT/HalCode9000.ailang" \
          "HalCode9000.x" \
          "$ROOT/cc_tools" \
          "hal"

if [[ $SELF_UPDATE -eq 1 && $APP_RUNNING -eq 1 ]]; then
    start_app
fi

log ""
log "build.sh: done"
[[ $COPY -eq 1 && $BUILD_MAIN -eq 1 ]] && log "Run:  cd $ROOT && ./HalCode9000.x" || true
