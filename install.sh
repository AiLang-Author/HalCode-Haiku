#!/usr/bin/env bash
# HalCode-Haiku install: build the agent and the AILang desk.
# The window is native Haiku and is built on the guest (make -C shell).
# Copyright (c) 2026 Sean Collins, 2 Paws Machine and Engineering. MIT.
#
# Usage:
#   ./install.sh
#   ./install.sh --skip-keys --skip-postgres --skip-olympus
#   On Haiku, scripts/haiku_postgres.sh is registered with UserBootscript
#   unless --skip-postgres is set. pkgman installs ctags for Relmem.
#   ./install.sh --no-build          # keys only, skip the compile
#   ./install.sh --no-desktop        # accepted, there is no Linux menu entry
set -euo pipefail

SKIP_KEYS=0
SKIP_POSTGRES=0
SKIP_OLYMPUS=0
NO_BUILD=0
NO_DESKTOP=0
DO_BUILD=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-keys) SKIP_KEYS=1; shift ;;
        --skip-postgres) SKIP_POSTGRES=1; shift ;;
        --skip-olympus) SKIP_OLYMPUS=1; shift ;;
        --no-build) NO_BUILD=1; shift ;;
        --build) DO_BUILD=1; shift ;;
        --no-desktop) NO_DESKTOP=1; shift ;;
        -h|--help)
            sed -n '2,12p' "$0" | sed 's/^# \?//'
            if [[ "$(uname -s 2>/dev/null || true)" == "Haiku" ]]; then
                printf '%s\n' \
                    "Haiku copies prebuilt native binaries into ~/config/non-packaged." \
                    "  ./install.sh --skip-keys" \
                    "  ./install.sh --build          # compile HalCode from this source tree" \
                    "The desk, the window, and the full-screen terminal UI are not installed."
            fi
            exit 0
            ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"
export HALCODE_ROOT="$ROOT"

log()  { printf '==> %s\n' "$*"; }
info() { printf '    %s\n' "$*"; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# Native Haiku install. Copies prebuilt binaries. Does not build the desk
# or the window, and does not call sys_compat_run. --build compiles the
# agent and the shipped tools from this source tree first.
install_haiku() {
    local arch prefix bin_dir app_dir payload stamp got want
    local hint dest inp profile marker line src dst tool

    arch="$(uname -m 2>/dev/null || true)"
    if [[ "$arch" != "x86_64" ]]; then
        die "Haiku ${arch:-unknown} is not supported. This package is x86_64."
    fi
    command -v curl >/dev/null 2>&1 || die "curl is not installed. Install it with: pkgman install curl"
    if [[ "$DO_BUILD" -eq 1 && "$NO_BUILD" -eq 1 ]]; then
        die "pass only one of --build and --no-build"
    fi

    prefix="${HOME}/config/non-packaged"
    bin_dir="${prefix}/bin"
    app_dir="${prefix}/lib/halcode"
    payload="${ROOT}/prebuilt/haiku-x86_64"
    [[ -n "$bin_dir" && "$bin_dir" == */config/non-packaged/bin ]] || die "refusing empty install prefix"

    if [[ "$DO_BUILD" -eq 1 ]]; then
        haiku_build_from_source "$payload"
    fi
    [[ -d "$payload" ]] || die "missing ${payload}. The default install copies prebuilt binaries. Pass --build only in a source tree."
    [[ -f "${ROOT}/cc_tools.haiku.json" ]] || die "missing ${ROOT}/cc_tools.haiku.json"

    log "Installing native HalCode into ${prefix}"
    mkdir -p "$bin_dir" "$app_dir" "${HOME}/.halcode"
    chmod 700 "${HOME}/.halcode"

    copy_file "${payload}/HalCode9000.x" "${app_dir}/HalCode9000.x" 755
    copy_file "${payload}/ailang_haiku" "${bin_dir}/ailang_haiku" 755
    copy_file "${payload}/analyzer_haiku" "${bin_dir}/analyzer_haiku" 755
    copy_tree "${payload}/Librarys" "${bin_dir}/Librarys"
    copy_file "${ROOT}/cc_tools.haiku.json" "${app_dir}/cc_tools.json" 644

    local -a tools=(
        cc_read_ipc.x cc_head_ipc.x cc_ls_ipc.x cc_write_ipc.x
        cc_bash_ipc.x cc_webfetch_ipc.x cc_relmem_ipc.x cc_pgmem_ipc.x
        cc_agent_ipc.x cc_edit_ipc.x cc_undo_ipc.x cc_find_ipc.x
        cc_grep_ipc.x cc_git_ipc.x cc_stat_ipc.x cc_wc_ipc.x
        cc_du_ipc.x cc_diff_ipc.x cc_olympus_ipc.x cc_mcp_ipc.x
        cc_skills_ipc.x cc_ailang_ipc.x cc_packager_ipc.x cc_vision_ipc.x
    )
    for tool in "${tools[@]}"; do
        copy_file "${payload}/${tool}" "${app_dir}/${tool}" 755
    done

    stamp="$(sha256sum "${bin_dir}/ailang_haiku" | awk '{print $1}')"
    printf '%s\n' "$stamp" > "${bin_dir}/ailang_haiku.sha256"
    chmod 644 "${bin_dir}/ailang_haiku.sha256"

    write_haiku_launcher "$bin_dir"

    # Haiku reads this file. The runtime does not choose it.
    # Replace a copy that is still the Linux stock prompt. Leave an edited file.
    prompt_src="${ROOT}/config/system_prompt.haiku.txt"
    [[ -f "$prompt_src" ]] || prompt_src="${ROOT}/config/system_prompt.txt"
    prompt_dest="${HOME}/.halcode/system_prompt.txt"
    linux_stock="${ROOT}/config/system_prompt.txt"
    if [[ -f "$prompt_src" ]]; then
        if [[ ! -f "$prompt_dest" ]] || { [[ -f "$linux_stock" ]] && cmp -s "$prompt_dest" "$linux_stock"; }; then
            cp "$prompt_src" "$prompt_dest"
            chmod 644 "$prompt_dest"
            info "wrote ~/.halcode/system_prompt.txt"
        fi
        if [[ ! -f "${HOME}/.halcode/halcode.json" ]]; then
            printf '%s\n' '{ "max_tokens": 16384, "system_prompt_file": "system_prompt.txt" }' \
                > "${HOME}/.halcode/halcode.json"
            chmod 644 "${HOME}/.halcode/halcode.json"
        fi
    fi

    haiku_ensure_path "$bin_dir"
    haiku_ctags
    if [[ "$SKIP_POSTGRES" -eq 0 ]]; then
        log "PostgreSQL boot service"
        "${ROOT}/scripts/haiku_postgres.sh" install
    else
        info "Skipping PostgreSQL (--skip-postgres)."
    fi
    haiku_keys

    log "Installed"
    info "prefix:   ${prefix}"
    info "launcher: ${bin_dir}/halcode"
    info "agent:    ${app_dir}/HalCode9000.x"
    info "compiler: ${bin_dir}/ailang_haiku"
    info "analyzer: ${bin_dir}/analyzer_haiku"
    info "tools:    ${app_dir}/cc_tools.json"
    info "Start an MCP server:  halcode --mcp"
    info "One headless turn:    halcode --agent deepseek:deepseek-flash"
    info "The prompt for --agent is stdin."
    info "The full-screen terminal UI is not installed."
    info "The desk and the window are not installed."
}

copy_file() {
    local src="$1" dst="$2" mode="$3"
    [[ -f "$src" ]] || die "missing ${src}"
    mkdir -p "$(dirname "$dst")"
    rm -f "$dst"
    cat "$src" > "$dst"
    chmod "$mode" "$dst"
}

copy_tree() {
    local src="$1" dst="$2"
    [[ -d "$src" ]] || die "missing ${src}"
    [[ -n "$dst" && "$dst" == */config/non-packaged/bin/Librarys ]] || die "refusing to replace ${dst}"
    rm -rf "$dst"
    mkdir -p "$(dirname "$dst")"
    cp -R "$src" "$dst"
}

write_haiku_launcher() {
    local bin_dir="$1"
    cat > "${bin_dir}/halcode" <<'EOF'
#!/bin/sh
# Native HalCode launcher. No desk and no sys_compat_run.
# Copyright 2026 Sean Collins, 2 Paws Machine and Engineering. MIT.
set -eu
BIN_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
APP_DIR=$(CDPATH= cd -- "$BIN_DIR/../lib/halcode" && pwd)
COMP="$BIN_DIR/ailang_haiku"
STAMP="$BIN_DIR/ailang_haiku.sha256"
if [ -f "$COMP" ] && [ -f "$STAMP" ]; then
    got=$(sha256sum "$COMP" | awk '{print $1}')
    want=$(awk 'NR==1 {print $1}' "$STAMP")
    if [ "$got" != "$want" ]; then
        echo "warning: ailang_haiku does not match ailang_haiku.sha256" >&2
    fi
elif [ -f "$COMP" ]; then
    echo "warning: ailang_haiku.sha256 is missing" >&2
fi
if [ "$#" -eq 0 ] || [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    echo "HalCode is installed in $APP_DIR"
    echo "The full-screen terminal UI is not installed."
    echo "The desk and the window are not installed."
    echo ""
    echo "Start an MCP server:"
    echo "  halcode --mcp"
    echo ""
    echo "One headless turn (the prompt is stdin):"
    echo "  halcode --agent deepseek:deepseek-flash"
    echo ""
    echo "Compiler:"
    echo "  ailang_haiku --haiku source.ailang out.x"
    exit 0
fi
# Workers and cc_tools.json live next to the agent. --agent reads
# ./cc_tools.json from the current directory and does not chdir itself.
cd "$APP_DIR"
exec "$APP_DIR/HalCode9000.x" "$@"
EOF
    chmod 755 "${bin_dir}/halcode"
}

haiku_ensure_path() {
    local bin_dir="$1" profile marker
    case ":${PATH}:" in
        *":${bin_dir}:"*) return 0 ;;
    esac
    profile="${HOME}/config/settings/profile"
    marker="# halcode non-packaged bin"
    mkdir -p "$(dirname "$profile")"
    if [[ -f "$profile" ]] && grep -q "$marker" "$profile"; then
        info "PATH line already in ${profile}"
        return 0
    fi
    printf '\n%s\nexport PATH="$HOME/config/non-packaged/bin:$PATH"\n' "$marker" >> "$profile"
    info "added \$HOME/config/non-packaged/bin to ${profile}"
    info "Open a new terminal, or run: export PATH=\"\$HOME/config/non-packaged/bin:\$PATH\""
}

haiku_ctags() {
    if command -v ctags >/dev/null 2>&1; then
        info "ctags already on PATH: $(command -v ctags)"
        return 0
    fi
    log "universal-ctags for Relmem"
    local ctags_ok=0
    if command -v pkgman >/dev/null 2>&1; then
        if pkgman install -y ctags; then
            if command -v ctags >/dev/null 2>&1; then
                ctags_ok=1
                info "ctags on PATH: $(command -v ctags)"
            fi
        fi
    fi
    if [[ "$ctags_ok" -eq 0 ]]; then
        info "WARNING: universal-ctags is not installed. Relmem will index 0 symbols until ctags is on PATH."
    fi
}

haiku_keys() {
    local hint dest inp
    if [[ "$SKIP_KEYS" -eq 1 ]]; then
        info "Skipping provider keys (--skip-keys)."
        info "A key file is ~/.halcode/<hint>_key with mode 600. Hints: deepseek, anthropic, xai."
        return 0
    fi
    mkdir -p "${HOME}/.halcode"
    chmod 700 "${HOME}/.halcode"
    log "Provider keys (Enter skips, existing files are kept)"
    for hint in deepseek anthropic xai; do
        dest="${HOME}/.halcode/${hint}_key"
        if [[ -f "$dest" ]]; then
            printf '  %s key [already set — Enter to keep, or paste a new key]: ' "$hint"
        else
            printf '  %s key (Enter to skip): ' "$hint"
        fi
        inp=""
        IFS= read -rs inp || inp=""
        printf '\n'
        if [[ -n "$inp" ]]; then
            printf '%s' "$inp" > "$dest"
            chmod 600 "$dest"
            info "${hint} key saved."
        elif [[ -f "$dest" ]]; then
            chmod 600 "$dest"
            info "${hint} key kept."
        else
            info "${hint} key skipped."
        fi
    done
}

haiku_build_from_source() {
    local payload="$1" cc libs stage out tool src
    [[ -x "${ROOT}/scripts/stage_platform.sh" ]] || die "--build needs the HalCode source tree (scripts/stage_platform.sh). The default install copies prebuilt binaries."
    [[ -f "${ROOT}/scripts/compile_halcode.sh" ]] || die "--build needs scripts/compile_halcode.sh"
    cc="${payload}/ailang_haiku"
    if [[ ! -x "$cc" ]]; then
        cc="$(command -v ailang_haiku || true)"
    fi
    [[ -n "$cc" && -x "$cc" ]] || die "--build needs ailang_haiku in ${payload} or on PATH"
    libs="$(CDPATH= cd -- "$(dirname "$cc")" && pwd)/Librarys"
    [[ -d "$libs" ]] || die "--build needs Librarys beside ${cc}"
    log "Compiling native HalCode (--build). The compiler and analyzer are not rebuilt."
    mkdir -p "$payload"
    HALCODE_CC="$cc" AILANG_LIB_PATH="$libs" \
        "${ROOT}/scripts/compile_halcode.sh" haiku "${payload}/HalCode9000.x" tui
    stage="/tmp/hc_install_stage_$$"
    "${ROOT}/scripts/stage_platform.sh" haiku "$stage" tui
    local -a tools=(
        cc_read_ipc cc_head_ipc cc_ls_ipc cc_write_ipc
        cc_bash_ipc cc_webfetch_ipc cc_relmem_ipc cc_pgmem_ipc
        cc_agent_ipc cc_edit_ipc cc_undo_ipc cc_find_ipc
        cc_grep_ipc cc_git_ipc cc_stat_ipc cc_wc_ipc
        cc_du_ipc cc_diff_ipc cc_olympus_ipc cc_mcp_ipc
        cc_skills_ipc cc_ailang_ipc cc_packager_ipc cc_vision_ipc
    )
    for tool in "${tools[@]}"; do
        src="${stage}/cc_tools/${tool}.ailang"
        out="${payload}/${tool}.x"
        [[ -f "$src" ]] || die "missing ${src}"
        info "compiling ${tool}"
        (
            cd "$stage"
            AILANG_LIB_PATH="$libs" env -u AILANG_LINSCAN \
                "$cc" -march=sse2 --haiku "cc_tools/${tool}.ailang" "$out"
        )
        [[ -f "$out" ]] || die "compile failed: ${tool}"
    done
    rm -rf "$stage"
}

if [[ "$(uname -s 2>/dev/null || true)" == "Haiku" ]]; then
    install_haiku
    exit 0
fi

if [[ "$DO_BUILD" -eq 1 ]]; then
    die "--build is for Haiku. Linux builds unless --no-build is set."
fi

if [[ -z "${AILANG_ROOT:-}" ]]; then
    if [[ -d "$HOME/Ailang-Self-Hosting-" ]]; then
        AILANG_ROOT="$HOME/Ailang-Self-Hosting-"
    elif command -v ailang.x >/dev/null 2>&1; then
        AILANG_ROOT="$(cd "$(dirname "$(readlink -f "$(command -v ailang.x)")")" && pwd)"
    else
        AILANG_ROOT=""
    fi
fi
export AILANG_ROOT

if [[ "$NO_BUILD" -eq 0 ]]; then
    command -v ailang.x >/dev/null 2>&1 || die "ailang.x not on PATH. Clone https://github.com/AiLang-Author/Ailang-Self-Hosting- and run its install_compiler.sh"

    log "Building agent + tools"
    ./build.sh

    log "Building desk (AILANG_ROOT=$AILANG_ROOT)"
    make -C shell desk AILANG_ROOT="$AILANG_ROOT"
    [[ -x "$ROOT/shell/halcode_desk.x" ]] || die "desk build failed"
    [[ -x "$ROOT/HalCode9000.x" ]] || die "agent binary missing"
    info "Haiku window: on the guest, make -C shell"
fi

info "The front end is shell/halcode_shell_haiku, built on Haiku with g++ -lbe."

log "Keys / pgmem / Olympus (same as TUI)"
SETUP_ARGS=()
[[ "$SKIP_KEYS" -eq 1 ]] && SETUP_ARGS+=(--skip-keys)
[[ "$SKIP_POSTGRES" -eq 1 ]] && SETUP_ARGS+=(--skip-postgres)
[[ "$SKIP_OLYMPUS" -eq 1 ]] && SETUP_ARGS+=(--skip-olympus)
"$ROOT/setup.sh" "${SETUP_ARGS[@]}"

if [[ ! -f "$HOME/.halcode/system_prompt.txt" && -f "$ROOT/config/system_prompt.txt" ]]; then
    mkdir -p "$HOME/.halcode"
    chmod 700 "$HOME/.halcode"
    cp "$ROOT/config/system_prompt.txt" "$HOME/.halcode/system_prompt.txt"
    if [[ ! -f "$HOME/.halcode/halcode.json" ]]; then
        printf '%s\n' '{ "max_tokens": 16384, "system_prompt_file": "system_prompt.txt" }' \
            > "$HOME/.halcode/halcode.json"
    fi
    info "wrote ~/.halcode/system_prompt.txt"
fi

log "Done"
info "Launch:  halcode"
info "Or:      $ROOT/scripts/launch_halcode.sh"
info "Prompt:  ~/.halcode/system_prompt.txt"
info "Rebuild: make -C $ROOT && halcode"
