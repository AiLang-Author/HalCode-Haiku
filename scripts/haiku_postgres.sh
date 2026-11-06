#!/bin/sh
# Install and start PostgreSQL on Haiku, including at every boot.
# Creates the databases the guest apps already look for:
#   cad_db         owner bob     (AILang CAD, TCP 127.0.0.1:5432 and /tmp)
#   ailang_system  owner $USER   (pgmem, socket /var/run/postgresql)
#   role nobody               (pgmem/relmem fallback when USER is unset)
# Idempotent. `install` also registers this file with UserBootscript.
# Copyright (c) 2026 Sean Collins, 2 Paws Machine and Engineering. MIT.

set -eu

PGDATA="${PGDATA:-$HOME/pgdata}"
PGLOG="$PGDATA/server.log"
BOOT_DIR="$HOME/config/settings/boot"
BOOT_COPY="$BOOT_DIR/haiku_postgres.sh"
BOOT_SCRIPT="$BOOT_DIR/UserBootscript"
MARKER="# haiku_postgres.sh"

die() { printf 'haiku_postgres: %s\n' "$*" >&2; exit 1; }
log() { printf 'haiku_postgres: %s\n' "$*"; }

pgbin() {
    if [ -x /boot/system/bin/pg_ctl ]; then
        printf '%s\n' /boot/system/bin
        return 0
    fi
    return 1
}

# Haiku's desk user is uid 0. pg_resetwal refuses euid 0, so the server
# runs as a normal account that owns PGDATA.
ensure_os_user() {
    if id postgres >/dev/null 2>&1; then
        return 0
    fi
    command -v useradd >/dev/null 2>&1 || die "need a non-root account to run postgres"
    log "creating account postgres"
    mkdir -p /boot/home/postgres
    useradd -d /boot/home/postgres -s /bin/bash postgres
    id postgres >/dev/null 2>&1 || die "could not create account postgres"
}

ensure_runas() {
    mkdir -p "$BOOT_DIR"
    if [ -x "$BOOT_DIR/haiku_runas" ]; then
        return 0
    fi
    src=$(dirname "$0")/haiku_runas.c
    [ -f "$src" ] || src=/boot/home/HalCode-Haiku/scripts/haiku_runas.c
    [ -f "$src" ] || die "missing haiku_runas.c"
    command -v gcc >/dev/null 2>&1 || die "gcc is required to build haiku_runas"
    gcc -O2 -o "$BOOT_DIR/haiku_runas" "$src"
    chmod 755 "$BOOT_DIR/haiku_runas"
}

as_pg() {
    ensure_runas
    "$BOOT_DIR/haiku_runas" postgres "$@"
}

install_package() {
    if pgbin >/dev/null 2>&1; then
        return 0
    fi
    command -v pkgman >/dev/null 2>&1 || die "postgresql is not installed and pkgman is missing"
    log "installing package postgresql"
    pkgman install -y postgresql
    pgbin >/dev/null 2>&1 || die "postgresql package did not provide pg_ctl"
}

ensure_data() {
    ensure_os_user
    if [ -f "$PGDATA/PG_VERSION" ]; then
        chown -R postgres:root "$PGDATA"
        return 0
    fi
    log "creating data directory $PGDATA"
    mkdir -p "$PGDATA"
    chown postgres:root "$PGDATA"
    as_pg "$(pgbin)/initdb" -D "$PGDATA" --locale=C --encoding=UTF8
}

ensure_socket_dir() {
    # pgmem opens /var/run/postgresql. On Haiku /var is /boot/system/var.
    # CAD also tries that path, then /tmp, then 127.0.0.1:5432.
    mkdir -p /var/run/postgresql 2>/dev/null || mkdir -p /boot/system/var/run/postgresql
    chmod 755 /var/run/postgresql 2>/dev/null || true
    if id postgres >/dev/null 2>&1; then
        chown postgres:root /var/run/postgresql 2>/dev/null || true
    fi
    if [ ! -d /var/run/postgresql ]; then
        die "could not create /var/run/postgresql"
    fi
}

ensure_conf() {
    conf="$PGDATA/postgresql.conf"
    [ -f "$conf" ] || die "missing $conf"
    # pgmem looks only at /var/run/postgresql. CAD also tries /tmp.
    if grep -q "^unix_socket_directories = '/tmp,/var/run/postgresql'" "$conf"; then
        return 0
    fi
    if grep -q '^unix_socket_directories' "$conf"; then
        sed -i "s|^unix_socket_directories = .*|unix_socket_directories = '/tmp,/var/run/postgresql'|" "$conf"
        return 0
    fi
    cat >> "$conf" << 'EOF'

# haiku_postgres.sh — CAD uses /tmp and 127.0.0.1, pgmem uses /var/run/postgresql
listen_addresses = '127.0.0.1'
port = 5432
unix_socket_directories = '/tmp,/var/run/postgresql'
EOF
}

clear_stale_pid() {
    pidfile="$PGDATA/postmaster.pid"
    [ -f "$pidfile" ] || return 0
    pid=$(head -n 1 "$pidfile" 2>/dev/null || true)
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        return 0
    fi
    log "removing stale postmaster.pid"
    rm -f "$pidfile"
}

server_ready() {
    "$(pgbin)/pg_isready" -h 127.0.0.1 -p 5432 >/dev/null 2>&1
}

log_at=0

start_once() {
    clear_stale_pid
    if [ -f "$PGLOG" ]; then
        log_at=$(wc -c < "$PGLOG")
    else
        log_at=0
    fi
    as_pg "$(pgbin)/pg_ctl" -D "$PGDATA" -l "$PGLOG" -w -t 60 start
}

this_start_torn() {
    dd if="$PGLOG" bs=1 skip="$log_at" 2>/dev/null \
        | grep -q "could not locate a valid checkpoint record"
}

start_server() {
    if server_ready; then
        log "already accepting connections on 127.0.0.1:5432"
        return 0
    fi
    log "starting postgres"
    if start_once; then
        server_ready || die "postgres did not become ready"
        return 0
    fi
    # An unclean guest reset leaves a torn WAL page. One resetwal, then retry.
    if this_start_torn; then
        log "WAL checkpoint is torn; resetting WAL and retrying"
        as_pg "$(pgbin)/pg_resetwal" -f -D "$PGDATA"
        start_once || die "postgres did not start after WAL reset"
        server_ready || die "postgres did not become ready after WAL reset"
        return 0
    fi
    die "postgres did not start; see $PGLOG"
}

psql_file() {
    sql=$1
    shift
    printf '%s\n' "$sql" > "$PGDATA/haiku_postgres.sql"
    chown postgres:root "$PGDATA/haiku_postgres.sql"
    as_pg "$(pgbin)/psql" -h /tmp -U user -d postgres -v ON_ERROR_STOP=1 "$@" -f "$PGDATA/haiku_postgres.sql"
}

psql_q() {
    psql_file "$1" -tA
}

ensure_role() {
    role=$1
    found=$(psql_q "SELECT 1 FROM pg_roles WHERE rolname='${role}'" || true)
    if printf '%s' "$found" | grep -q 1; then
        return 0
    fi
    log "creating role ${role}"
    psql_file "CREATE ROLE \"${role}\" LOGIN;"
}

ensure_db() {
    name=$1
    owner=$2
    found=$(psql_q "SELECT 1 FROM pg_database WHERE datname='${name}'" || true)
    if printf '%s' "$found" | grep -q 1; then
        return 0
    fi
    log "creating database ${name}"
    psql_file "CREATE DATABASE \"${name}\" OWNER \"${owner}\";"
}

grant_nobody() {
    # The memory tools use $USER, and the literal nobody when that
    # variable is missing. The loader used to start them with an empty
    # environment, so this role has to exist or they exit before listen.
    psql_file "GRANT ALL PRIVILEGES ON DATABASE ailang_system TO nobody;"
    psql_file "GRANT ALL ON SCHEMA public TO nobody;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO nobody;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO nobody;" -d ailang_system
}

ensure_databases() {
    me=$(whoami)
    ensure_role "$me"
    ensure_role bob
    ensure_role nobody
    ensure_db ailang_system "$me"
    ensure_db cad_db bob
    grant_nobody
    log "databases ready (ailang_system owner ${me}, cad_db owner bob, role nobody)"
}

install_boot() {
    mkdir -p "$BOOT_DIR"
    if [ "$(cd "$(dirname "$0")" && pwd)/$(basename "$0")" != "$BOOT_COPY" ]; then
        cp "$0" "$BOOT_COPY"
    fi
    chmod 755 "$BOOT_COPY"
    if [ -f "$BOOT_SCRIPT" ] && grep -q "$MARKER" "$BOOT_SCRIPT"; then
        log "UserBootscript already starts postgres"
        return 0
    fi
    [ -f "$BOOT_SCRIPT" ] || die "missing $BOOT_SCRIPT"
    cat >> "$BOOT_SCRIPT" << EOF

$MARKER
if [ -x "\$HOME/config/settings/boot/haiku_postgres.sh" ]; then
	"\$HOME/config/settings/boot/haiku_postgres.sh" start >> "\$HOME/pgdata/boot.log" 2>&1 &
fi
EOF
    log "registered boot start in UserBootscript"
}

cmd=${1:-start}
case "$cmd" in
    install)
        install_package
        ensure_data
        ensure_socket_dir
        ensure_conf
        install_boot
        start_server
        ensure_databases
        ;;
    start)
        install_package
        ensure_data
        ensure_socket_dir
        ensure_conf
        start_server
        ensure_databases
        ;;
    *)
        die "usage: haiku_postgres.sh [install|start]"
        ;;
esac
