#!/usr/bin/env bash
# =============================================================================
# HalCode9000 — One-Shot Setup
# Copyright (c) 2026 Sean Collins, 2 Paws Machine and Engineering
# License: MIT
#
# Usage:
#   ./setup.sh                  # interactive (recommended)
#   ./setup.sh --skip-postgres  # skip PostgreSQL setup
#   ./setup.sh --skip-olympus   # skip OlympusRepo setup
#   ./setup.sh --skip-keys      # skip API key prompts (re-run later)
# =============================================================================

set -euo pipefail

# ── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'

info()    { /usr/bin/echo -e "${CYAN}→${RESET} $*"; }
success() { /usr/bin/echo -e "${GREEN}✓${RESET} $*"; }
warn()    { /usr/bin/echo -e "${YELLOW}⚠${RESET}  $*"; }
error()   { /usr/bin/echo -e "${RED}✗${RESET} $*"; exit 1; }
ask()     { /usr/bin/echo -e "${BOLD}$*${RESET}"; }
note()    { /usr/bin/echo -e "${DIM}  $*${RESET}"; }
divider() { /usr/bin/echo -e "${CYAN}────────────────────────────────────────────────────${RESET}"; }
banner()  {
  /usr/bin/echo ""
  /usr/bin/echo -e "${CYAN}${BOLD}"
  /usr/bin/echo "  ██╗  ██╗ █████╗ ██╗      ██████╗ ██████╗ ██████╗ ███████╗"
  /usr/bin/echo "  ██║  ██║██╔══██╗██║     ██╔════╝██╔═══██╗██╔══██╗██╔════╝"
  /usr/bin/echo "  ███████║███████║██║     ██║     ██║   ██║██║  ██║█████╗  "
  /usr/bin/echo "  ██╔══██║██╔══██║██║     ██║     ██║   ██║██║  ██║██╔══╝  "
  /usr/bin/echo "  ██║  ██║██║  ██║███████╗╚██████╗╚██████╔╝██████╔╝███████╗"
  /usr/bin/echo "  ╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝ ╚═════╝ ╚═════╝ ╚═════╝ ╚══════╝"
  /usr/bin/echo ""
  /usr/bin/echo "       ██████╗  ██████╗  ██████╗  ██████╗ "
  /usr/bin/echo "       ╚════██╗██╔═══██╗██╔═══██╗██╔═══██╗"
  /usr/bin/echo "        █████╔╝██║   ██║██║   ██║██║   ██║"
  /usr/bin/echo "        ╚═══██╗██║   ██║██║   ██║██║   ██║"
  /usr/bin/echo "       ██████╔╝╚██████╔╝╚██████╔╝╚██████╔╝"
  /usr/bin/echo "       ╚═════╝  ╚═════╝  ╚═════╝  ╚═════╝ "
  /usr/bin/echo -e "${RESET}"
  /usr/bin/echo -e "  ${BOLD}Agentic AI coding assistant — built in AILang.${RESET}"
  /usr/bin/echo ""
}

# ── Arg flags ────────────────────────────────────────────────────────────────
SKIP_POSTGRES=0; SKIP_OLYMPUS=0; SKIP_KEYS=0
while [[ $# -gt 0 ]]; do
  case $1 in
    --skip-postgres) SKIP_POSTGRES=1; shift ;;
    --skip-olympus)  SKIP_OLYMPUS=1;  shift ;;
    --skip-keys)     SKIP_KEYS=1;     shift ;;
    *) warn "Unknown argument: $1"; shift ;;
  esac
done

# ── Paths ────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEYSTORE_DIR="$HOME/.halcode"
KEYSTORE_FILE="$KEYSTORE_DIR/keys.env"
OLYMPUS_DEFAULT_DIR="$HOME/OlympusRepo"

# =============================================================================
banner

OS="unknown"
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
  if /usr/bin/grep -qi microsoft /proc/version 2>/dev/null; then OS="wsl2"
  else OS="linux"; fi
elif [[ "$OSTYPE" == "darwin"* ]]; then OS="macos"; fi

info "Detected OS: ${BOLD}$OS${RESET}"
info "Install dir: ${BOLD}$SCRIPT_DIR${RESET}"
info "Key store:   ${BOLD}$KEYSTORE_FILE${RESET}"
echo ""

# =============================================================================
# STEP 1 — PostgreSQL
# =============================================================================
divider
echo -e "${BOLD}  STEP 1 — PostgreSQL (required for persistent memory)${RESET}"
divider
note "HalCode9000's memory tools (pgmem) store context in a local PostgreSQL database."
note "Without it, pgmem falls back to no-op but the assistant loses long-term memory."
echo ""

if [[ "$SKIP_POSTGRES" -eq 1 ]]; then
  warn "Skipping PostgreSQL setup (--skip-postgres)."
else
  PG_OK=0
  if command -v psql &>/dev/null && pg_isready -h 127.0.0.1 &>/dev/null 2>&1; then
    success "PostgreSQL is already running."
    PG_OK=1
  elif command -v psql &>/dev/null; then
    warn "psql found but server is not running."
  else
    warn "PostgreSQL not found."
  fi

  if [[ "$PG_OK" -eq 0 ]]; then
    read -rp "  Install and start PostgreSQL now? [Y/n]: " pg_install
    if [[ "${pg_install:-Y}" =~ ^[Yy]$ ]]; then
      if [[ "$OS" == "wsl2" || "$OS" == "linux" ]]; then
        info "Installing postgresql..."
        sudo apt-get update -qq && sudo apt-get install -y postgresql postgresql-contrib
        info "Starting PostgreSQL..."
        sudo service postgresql start || sudo systemctl start postgresql
      elif [[ "$OS" == "macos" ]]; then
        command -v brew &>/dev/null || error "Homebrew not found. Install from https://brew.sh first."
        brew install postgresql@16
        brew services start postgresql@16
        sleep 2
      else
        error "Unsupported OS for auto-install. Install PostgreSQL manually and re-run."
      fi
      if pg_isready -h 127.0.0.1 &>/dev/null 2>&1; then
        success "PostgreSQL is now running."
        PG_OK=1
      else
        error "PostgreSQL still not responding after install. Check logs and re-run."
      fi
    else
      warn "Skipping PostgreSQL. pgmem tool will be non-functional."
    fi
  fi

  # Auto-start on WSL2
  if [[ "$OS" == "wsl2" && "$PG_OK" -eq 1 ]]; then
    RC_FILE="$HOME/.bashrc"
    [[ "$SHELL" == */zsh ]] && RC_FILE="$HOME/.zshrc"
    if ! /usr/bin/grep -q "service postgresql start" "$RC_FILE" 2>/dev/null; then
      read -rp "  Auto-start PostgreSQL when you open a terminal? [Y/n]: " pg_auto
      if [[ "${pg_auto:-Y}" =~ ^[Yy]$ ]]; then
        /usr/bin/echo 'sudo service postgresql start > /dev/null 2>&1' >> "$RC_FILE"
        success "Added PostgreSQL auto-start to $RC_FILE"
      fi
    fi
  fi

  # Create halcode DB user and database
  if [[ "$PG_OK" -eq 1 ]]; then
    HC_DB_USER="halcode"
    HC_DB_NAME="halcode"

    # Generate a random password if not already set
    EXISTING_PG_PASS=""
    [[ -f "$KEYSTORE_FILE" ]] && EXISTING_PG_PASS=$(grep "^HC_PG_PASS=" "$KEYSTORE_FILE" 2>/dev/null | cut -d= -f2- || true)

    if [[ -n "$EXISTING_PG_PASS" ]]; then
      HC_DB_PASS="$EXISTING_PG_PASS"
      info "Using existing PostgreSQL password from keystore."
    else
      HC_DB_PASS=$(tr -dc 'A-Za-z0-9!@#%^&*' < /dev/urandom | head -c 24 2>/dev/null || \
                  python3 -c "import secrets,string; print(secrets.token_urlsafe(18))")
      info "Generated new PostgreSQL password."
    fi

    # Create role
    PG_CMD_PREFIX="sudo -u postgres psql"
    command -v sudo &>/dev/null || PG_CMD_PREFIX="psql postgres"

    $PG_CMD_PREFIX -v ON_ERROR_STOP=1 -c \
      "DO \$\$ BEGIN
         IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='${HC_DB_USER}') THEN
           CREATE USER ${HC_DB_USER} WITH PASSWORD '${HC_DB_PASS}'
             NOSUPERUSER NOCREATEDB NOCREATEROLE INHERIT LOGIN;
         ELSE
           ALTER USER ${HC_DB_USER} WITH PASSWORD '${HC_DB_PASS}';
         END IF;
       END \$\$;" 2>/dev/null || warn "Could not create halcode DB user — may already exist."

    DB_EXISTS=$($PG_CMD_PREFIX -tAq -c \
      "SELECT 1 FROM pg_database WHERE datname='${HC_DB_NAME}'" 2>/dev/null || true)
    if [[ "$DB_EXISTS" != "1" ]]; then
      $PG_CMD_PREFIX -c "CREATE DATABASE ${HC_DB_NAME} OWNER ${HC_DB_USER};" 2>/dev/null \
        || warn "Could not create halcode database — may already exist."
    fi

    success "PostgreSQL user '${HC_DB_USER}' and database '${HC_DB_NAME}' ready."

    # Save pg connection to keystore
    mkdir -p "$KEYSTORE_DIR" && chmod 700 "$KEYSTORE_DIR"
    {
      echo "HC_PG_USER=${HC_DB_USER}"
      echo "HC_PG_NAME=${HC_DB_NAME}"
      echo "HC_PG_HOST=127.0.0.1"
      echo "HC_PG_PORT=5432"
      echo "HC_PG_PASS=${HC_DB_PASS}"
    } >> "$KEYSTORE_FILE.tmp"
  fi
fi

echo ""

# =============================================================================
# STEP 2 — OlympusRepo
# =============================================================================
divider
echo -e "${BOLD}  STEP 2 — OlympusRepo (required for code-aware memory / relmem)${RESET}"
divider
note "The relmem tool indexes your repositories via OlympusRepo so HalCode9000 can"
note "answer questions like 'where is X defined?' across your entire codebase."
echo ""

if [[ "$SKIP_OLYMPUS" -eq 1 ]]; then
  warn "Skipping OlympusRepo setup (--skip-olympus)."
else
  OLYMPUS_OK=0
  OLYMPUS_URL=""

  # Check if already running
  if curl -sf http://localhost:8000/ &>/dev/null 2>&1; then
    success "OlympusRepo is already running at http://localhost:8000."
    OLYMPUS_URL="http://localhost:8000"
    OLYMPUS_OK=1
  else
    warn "OlympusRepo is not running on localhost:8000."
  fi

  if [[ "$OLYMPUS_OK" -eq 0 ]]; then
    read -rp "  Do you want to install/start OlympusRepo now? [Y/n]: " olympus_install
    if [[ "${olympus_install:-Y}" =~ ^[Yy]$ ]]; then

      # Check if already cloned somewhere
      OLYMPUS_DIR=""
      if [[ -d "$OLYMPUS_DEFAULT_DIR" && -f "$OLYMPUS_DEFAULT_DIR/setup.sh" ]]; then
        OLYMPUS_DIR="$OLYMPUS_DEFAULT_DIR"
        info "Found existing OlympusRepo at $OLYMPUS_DIR"
      else
        read -rp "  Where should OlympusRepo be installed? [$OLYMPUS_DEFAULT_DIR]: " inp
        OLYMPUS_DIR="${inp:-$OLYMPUS_DEFAULT_DIR}"
        if [[ ! -d "$OLYMPUS_DIR" ]]; then
          info "Cloning OlympusRepo..."
          git clone https://github.com/AiLang-Author/OlympusRepo.git "$OLYMPUS_DIR" \
            || error "Clone failed. Check your network connection and try again."
        fi
      fi

      # Run OlympusRepo setup if .env not present
      if [[ ! -f "$OLYMPUS_DIR/.env" ]]; then
        info "Running OlympusRepo setup wizard..."
        bash "$OLYMPUS_DIR/setup.sh" || error "OlympusRepo setup failed."
      else
        info "OlympusRepo .env already present, skipping its setup wizard."
      fi

      # Try to start it
      read -rp "  Start OlympusRepo server now? [Y/n]: " olympus_start
      if [[ "${olympus_start:-Y}" =~ ^[Yy]$ ]]; then
        info "Starting OlympusRepo (background)..."
        cd "$OLYMPUS_DIR"
        set -a; source .env; set +a
        nohup uvicorn olympusrepo.web.app:app --host 0.0.0.0 --port 8000 \
          > /tmp/olympusrepo.log 2>&1 &
        sleep 2
        cd "$SCRIPT_DIR"
        if curl -sf http://localhost:8000/ &>/dev/null 2>&1; then
          success "OlympusRepo is running at http://localhost:8000"
          OLYMPUS_URL="http://localhost:8000"
          OLYMPUS_OK=1
        else
          warn "OlympusRepo didn't respond after start. Check /tmp/olympusrepo.log."
          warn "Start manually:  cd $OLYMPUS_DIR && source .env && uvicorn olympusrepo.web.app:app --port 8000"
        fi
      fi
    else
      warn "Skipping OlympusRepo. relmem tool will be limited to local file indexing only."
    fi
  fi

  if [[ -n "$OLYMPUS_URL" ]]; then
    mkdir -p "$KEYSTORE_DIR" && chmod 700 "$KEYSTORE_DIR"
    echo "HC_OLYMPUS_URL=${OLYMPUS_URL}" >> "$KEYSTORE_FILE.tmp"
  fi
fi

echo ""

# =============================================================================
# STEP 3 — API Keys
# =============================================================================
divider
echo -e "${BOLD}  STEP 3 — API Keys${RESET}"
divider
note "Keys are stored in ${KEYSTORE_FILE} (chmod 600, never committed to git)."
note "Press Enter to skip any provider you don't use."
echo ""

if [[ "$SKIP_KEYS" -eq 1 ]]; then
  warn "Skipping API key setup (--skip-keys). Edit $KEYSTORE_FILE manually."
else
  # Load existing keys so we can show which are already set
  declare -A EXISTING_KEYS
  if [[ -f "$KEYSTORE_FILE" ]]; then
    while IFS='=' read -r k v; do
      [[ "$k" =~ ^HC_ ]] && EXISTING_KEYS["$k"]="$v"
    done < "$KEYSTORE_FILE"
  fi

  prompt_key() {
    local var_name="$1"; local display_name="$2"; local hint="$3"
    local existing="${EXISTING_KEYS[$var_name]:-}"
    if [[ -n "$existing" ]]; then
      local masked="${existing:0:8}..."
      read -rp "  ${display_name} [${masked} — Enter to keep, or paste new key]: " inp
    else
      read -rp "  ${display_name} (${hint}): " inp
    fi
    if [[ -n "$inp" ]]; then
      echo "${var_name}=${inp}" >> "$KEYSTORE_FILE.tmp"
      success "${display_name} saved."
    elif [[ -n "$existing" ]]; then
      echo "${var_name}=${existing}" >> "$KEYSTORE_FILE.tmp"
      success "${display_name} kept (existing)."
    else
      note "${display_name} skipped."
    fi
  }

  # Run provider model aggregator to ensure provider JSON specs are fresh
  if command -v python3 &>/dev/null && [[ -f "$SCRIPT_DIR/scripts/fetch_providers.py" ]]; then
    info "Aggregating provider specifications..."
    python3 "$SCRIPT_DIR/scripts/fetch_providers.py" >/dev/null 2>&1 || true
  fi

  echo -e "  ${BOLD}Configured providers:${RESET}"
  
  # Scan all provider JSON files for key_env requirements
  for pjson in "$SCRIPT_DIR/providers"/*.json "$KEYSTORE_DIR/providers"/*.json; do
    [[ -f "$pjson" ]] || continue
    P_NAME=$(grep -o '"name": *"[^"]*"' "$pjson" | head -n1 | cut -d'"' -f4 || true)
    P_ENV=$(grep -o '"key_env": *"[^"]*"' "$pjson" | head -n1 | cut -d'"' -f4 || true)
    [[ -z "$P_NAME" || -z "$P_ENV" ]] && continue
    
    # Map key_env to HC_ prefix if needed or store environment key directly
    HC_VAR="HC_${P_ENV}"
    prompt_key "$HC_VAR" "${P_NAME} API key (${P_ENV})" "from ${P_NAME} portal"
  done
fi

echo ""

# =============================================================================
# STEP 4 — Write keystore
# =============================================================================
divider
echo -e "${BOLD}  STEP 4 — Saving configuration${RESET}"
divider

mkdir -p "$KEYSTORE_DIR" && chmod 700 "$KEYSTORE_DIR"

# Merge: start from existing keystore, override with anything newly collected
MERGED="$KEYSTORE_FILE.merged"
> "$MERGED"

# Keys collected this run
if [[ -f "$KEYSTORE_FILE.tmp" ]]; then
  declare -A NEW_KEYS
  while IFS='=' read -r k v; do
    [[ -n "$k" ]] && NEW_KEYS["$k"]="$v"
  done < "$KEYSTORE_FILE.tmp"

  # Keep existing keys not overridden this run
  if [[ -f "$KEYSTORE_FILE" ]]; then
    while IFS='=' read -r k v; do
      [[ -z "${NEW_KEYS[$k]+x}" ]] && echo "${k}=${v}" >> "$MERGED"
    done < "$KEYSTORE_FILE"
  fi

  # Write new/updated keys
  for k in "${!NEW_KEYS[@]}"; do
    echo "${k}=${NEW_KEYS[$k]}" >> "$MERGED"
  done

  mv "$MERGED" "$KEYSTORE_FILE"
  rm -f "$KEYSTORE_FILE.tmp"
fi

chmod 600 "$KEYSTORE_FILE" 2>/dev/null || true

success "Configuration saved to ${KEYSTORE_FILE}"

# =============================================================================
# STEP 5 — Verify binaries
# =============================================================================
divider
echo -e "${BOLD}  STEP 5 — Binary check${RESET}"
divider

BINS=(
  HalCode9000.x
  cc_read_ipc.x cc_write_ipc.x cc_edit_ipc.x cc_bash_ipc.x
  cc_ls_ipc.x cc_head_ipc.x cc_find_ipc.x cc_grep_ipc.x
  cc_git_ipc.x cc_webfetch_ipc.x cc_mcp_ipc.x
  cc_agent_ipc.x cc_pgmem_ipc.x cc_relmem_ipc.x
  cc_ailang_lsp_ipc.x
)

ALL_OK=1
for b in "${BINS[@]}"; do
  if [[ -x "$SCRIPT_DIR/$b" ]]; then
    success "$b"
  else
    warn "$b — NOT FOUND or not executable"
    ALL_OK=0
  fi
done

if [[ "$ALL_OK" -eq 0 ]]; then
  echo ""
  warn "Some binaries are missing. To build from source (requires ailang.x compiler):"
  /usr/bin/echo -e "${DIM}"
  /usr/bin/echo "  cd /path/to/AILangSH"
  /usr/bin/echo "  ./ailang.x Applications/HalCode9000/HalCode9000.ailang Applications/HalCode9000/HalCode9000.x"
  /usr/bin/echo "  # Repeat for each cc_tools/cc_*_ipc.ailang"
  /usr/bin/echo -e "${RESET}"
  warn "Or download prebuilt binaries from the GitHub releases page."
fi

echo ""

# =============================================================================
# STEP 6 — Register MCP server with Claude Code
# =============================================================================
divider
echo -e "${BOLD}  STEP 6 — MCP server registration${RESET}"
divider

MCP_REGISTERED=0
if command -v claude &>/dev/null; then
  info "Registering HalCode9000 as an MCP server in Claude Code..."
  if claude mcp add halcode9000 -- "${SCRIPT_DIR}/HalCode9000.x" --mcp 2>/dev/null; then
    success "MCP server 'halcode9000' registered."
    MCP_REGISTERED=1
  else
    warn "claude mcp add failed — you may need to register manually:"
    note "  claude mcp add halcode9000 -- ${SCRIPT_DIR}/HalCode9000.x --mcp"
  fi
else
  warn "claude CLI not found on PATH. To register manually after installing Claude Code:"
  note "  claude mcp add halcode9000 -- ${SCRIPT_DIR}/HalCode9000.x --mcp"
fi

echo ""

# =============================================================================
# Done
# =============================================================================
divider
/usr/bin/echo ""
/usr/bin/echo -e "${GREEN}${BOLD}  Setup complete.${RESET}"
/usr/bin/echo ""
/usr/bin/echo -e "  To start HalCode GTK:"
/usr/bin/echo -e "    ${BOLD}halcode${RESET}"
/usr/bin/echo -e "    ${BOLD}${SCRIPT_DIR}/scripts/launch_halcode.sh${RESET}"
/usr/bin/echo ""
/usr/bin/echo -e "  Headless agent / TUI binary:"
/usr/bin/echo -e "    ${BOLD}source ${KEYSTORE_FILE}${RESET}"
/usr/bin/echo -e "    ${BOLD}cd ${SCRIPT_DIR} && ./HalCode9000.x${RESET}"
/usr/bin/echo ""
if [[ "$MCP_REGISTERED" -eq 1 ]]; then
  /usr/bin/echo -e "  MCP server: ${GREEN}registered${RESET} — restart Claude Code to activate."
else
  /usr/bin/echo -e "  MCP server: ${YELLOW}not registered${RESET} — run:"
  /usr/bin/echo -e "    ${BOLD}claude mcp add halcode9000 -- ${SCRIPT_DIR}/HalCode9000.x --mcp${RESET}"
fi
/usr/bin/echo ""
if [[ -n "${OLYMPUS_URL:-}" ]]; then
  /usr/bin/echo -e "  OlympusRepo is at: ${BOLD}${OLYMPUS_URL}${RESET}"
fi
/usr/bin/echo ""
divider
