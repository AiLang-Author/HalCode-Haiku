#!/usr/bin/env bash
# Register HalCode GTK in the Linux Applications menu (user install).
# Points at this source tree so `make -C shell` then relaunch updates in place.
# Copyright (c) 2026 Sean Collins, 2 Paws Machine and Engineering. MIT.
set -euo pipefail

log()  { printf '==> %s\n' "$*"; }
info() { printf '    %s\n' "$*"; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

UNINSTALL=0
WANT_DESKTOP_LINK=1
while [[ $# -gt 0 ]]; do
    case "$1" in
        --uninstall) UNINSTALL=1; shift ;;
        --no-desktop-link) WANT_DESKTOP_LINK=0; shift ;;
        -h|--help)
            cat <<'EOF'
Install HalCode GTK into the Applications menu.

  ./install_desktop.sh                 user install (~/.local/share/applications)
  ./install_desktop.sh --uninstall     remove the menu entry
  ./install_desktop.sh --no-desktop-link
EOF
            exit 0
            ;;
        *) die "unknown option: $1" ;;
    esac
done

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
EXEC="$ROOT/scripts/launch_halcode.sh"
ICON_SRC="$ROOT/desktop/halcode9000.png"
ICON256="$ROOT/desktop/halcode9000-256.png"

APP_ID="halcode9000"
DESKTOP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
ICON_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor"
DESKTOP_FILE="$DESKTOP_DIR/${APP_ID}.desktop"
USER_DESKTOP="${XDG_DESKTOP_DIR:-$HOME/Desktop}"
BIN_DIR="$HOME/.local/bin"

uninstall() {
    rm -f "$DESKTOP_FILE" \
          "$ICON_DIR/128x128/apps/${APP_ID}.png" \
          "$ICON_DIR/256x256/apps/${APP_ID}.png" \
          "$USER_DESKTOP/${APP_ID}.desktop" \
          "$BIN_DIR/halcode" \
          "$BIN_DIR/lastlog"
    update-desktop-database "$DESKTOP_DIR" 2>/dev/null || true
    gtk-update-icon-cache -f "$ICON_DIR" 2>/dev/null || true
    log "Removed Applications menu entry ($APP_ID)"
}

if [[ "$UNINSTALL" -eq 1 ]]; then
    uninstall
    exit 0
fi

[[ -x "$EXEC" ]] || chmod +x "$EXEC"
[[ -x "$EXEC" ]] || die "launcher not executable: $EXEC"

mkdir -p "$DESKTOP_DIR" \
         "$ICON_DIR/128x128/apps" \
         "$ICON_DIR/256x256/apps" \
         "$BIN_DIR"

if [[ -f "$ICON_SRC" ]]; then
    cp -f "$ICON_SRC" "$ICON_DIR/128x128/apps/${APP_ID}.png"
    if [[ -f "$ICON256" ]]; then
        cp -f "$ICON256" "$ICON_DIR/256x256/apps/${APP_ID}.png"
    else
        cp -f "$ICON_SRC" "$ICON_DIR/256x256/apps/${APP_ID}.png"
    fi
fi

cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Version=1.0
Name=HalCode9000
GenericName=HalCode
Comment=HalCode GTK agent desk
Exec=$EXEC
TryExec=$EXEC
Icon=$APP_ID
Terminal=false
Categories=Development;IDE;
Keywords=HalCode;AI;agent;Ailang;
StartupNotify=true
StartupWMClass=halcode_shell_gtk
Path=$ROOT
EOF
chmod 644 "$DESKTOP_FILE"

ln -sfn "$EXEC" "$BIN_DIR/halcode"
chmod +x "$EXEC"

LASTLOG="$ROOT/scripts/lastlog.sh"
if [[ -f "$LASTLOG" ]]; then
    chmod +x "$LASTLOG"
    ln -sfn "$LASTLOG" "$BIN_DIR/lastlog"
fi

if [[ "$WANT_DESKTOP_LINK" -eq 1 && -d "$USER_DESKTOP" ]]; then
    cp -f "$DESKTOP_FILE" "$USER_DESKTOP/${APP_ID}.desktop"
    chmod 644 "$USER_DESKTOP/${APP_ID}.desktop"
    gio set "$USER_DESKTOP/${APP_ID}.desktop" metadata::trusted true 2>/dev/null || true
    chmod +x "$USER_DESKTOP/${APP_ID}.desktop"
fi

update-desktop-database "$DESKTOP_DIR" 2>/dev/null || true
gtk-update-icon-cache -f "$ICON_DIR" 2>/dev/null || true
xdg-desktop-menu forceupdate 2>/dev/null || true

log "Applications menu: HalCode9000"
info "launcher: $EXEC"
info "desktop:  $DESKTOP_FILE"
info "command:  $BIN_DIR/halcode"
info "lastlog:  $BIN_DIR/lastlog"
info "Rebuild in place: make -C $ROOT/shell desk halcode_shell_gtk"
info "Then open HalCode9000 again (replaces the running window)."
