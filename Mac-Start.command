#!/bin/bash
# ============================================================
# U-Hermes - all-in-one launcher (macOS)
#   - First run: downloads Python + installs deps into portable/app/
#   - Subsequent runs: launches directly
# Double-click to start / 双击启动
# ============================================================
set -e

_LAUNCHER_DIR="$(cd "$(dirname "$0")" && pwd)"
UHERMES_DIR="$_LAUNCHER_DIR/portable"
if [ ! -d "$UHERMES_DIR" ]; then
    echo "  [ERROR] portable/ directory not found next to this launcher."
    echo "  Expected: $UHERMES_DIR"
    read -p "  Press Enter to exit..."
    exit 1
fi
APP_DIR="$UHERMES_DIR/app"
RUNTIME_DIR="$APP_DIR/runtime"
PACKAGES_DIR="$APP_DIR/packages"
WEBUI_DIR="$UHERMES_DIR/webui"
DATA_DIR="$UHERMES_DIR/data"
HERMES_HOME="$DATA_DIR/.hermes"

PYTHON_TAG="20260510"
PYTHON_VERSION="3.11.15"
GH_RAW="https://github.com/"
GH_ACCEL="https://ghfast.top/"
PYTHON_RELEASE_PATH="astral-sh/python-build-standalone/releases/download/$PYTHON_TAG"
PIP_MIRROR="https://pypi.tuna.tsinghua.edu.cn/simple"

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; NC='\033[0m'

echo ""
echo -e "${CYAN}"
echo "  ╔══════════════════════════════════════╗"
echo "  ║     ⚕ U-Hermes v0.1                 ║"
echo "  ║     Portable AI Agent               ║"
echo "  ╚══════════════════════════════════════╝"
echo -e "${NC}"

# ---- Detect CPU & set Python path ----
ARCH=$(uname -m)
if [ "$ARCH" = "arm64" ]; then
    PYTHON_DIR="$RUNTIME_DIR/python-mac-arm64"
    PY_PLATFORM_TAG="aarch64-apple-darwin"
    echo -e "  ${GREEN}Apple Silicon (M series)${NC}"
elif [ "$ARCH" = "x86_64" ]; then
    PYTHON_DIR="$RUNTIME_DIR/python-mac-x64"
    PY_PLATFORM_TAG="x86_64-apple-darwin"
    echo -e "  ${GREEN}Intel Mac (x64)${NC}"
else
    echo -e "  ${RED}Unsupported architecture: $ARCH${NC}"
    read -p "  Press Enter to exit..."
    exit 1
fi
PYTHON_BIN="$PYTHON_DIR/bin/python3"

# ---- Decide: setup needed? ----
need_setup() {
    [ ! -f "$PYTHON_BIN" ] && return 0
    "$PYTHON_BIN" -c "import sys; sys.path.insert(0,'$PACKAGES_DIR'); import run_agent" 2>/dev/null || return 0
    return 1
}

# ---- Detect China network (used by both setup & launch) ----
detect_china() {
    IN_CHINA=false
    if curl -s --max-time 3 -o /dev/null "https://pypi.tuna.tsinghua.edu.cn/" 2>/dev/null; then
        if ! curl -s --max-time 3 -o /dev/null "https://github.com/" 2>/dev/null; then
            IN_CHINA=true
        fi
    fi
}

download_gh() {
    local path="$1" output="$2"
    if [ "$IN_CHINA" = "true" ]; then
        echo -e "    ${CYAN}trying ghfast.top mirror...${NC}"
        if curl -fSL --max-time 300 "${GH_ACCEL}${GH_RAW}${path}" -o "$output" 2>/dev/null; then
            return 0
        fi
        echo -e "    ${YELLOW}mirror failed, trying direct...${NC}"
    fi
    curl -fSL "${GH_RAW}${path}" -o "$output"
}

pip_install_to_target() {
    if [ "$IN_CHINA" = "true" ]; then
        "$PYTHON_BIN" -m pip install "$@" --target "$PACKAGES_DIR" \
            --no-user --disable-pip-version-check --quiet -i "$PIP_MIRROR"
    else
        "$PYTHON_BIN" -m pip install "$@" --target "$PACKAGES_DIR" \
            --no-user --disable-pip-version-check --quiet
    fi
}

do_setup() {
    echo -e "  ${YELLOW}[SETUP] First-time setup detected. This will take a few minutes.${NC}"
    echo ""
    detect_china
    if [ "$IN_CHINA" = "true" ]; then
        echo -e "  Network: ${YELLOW}China (using mirrors)${NC}"
    else
        echo -e "  Network: ${GREEN}Direct${NC}"
    fi
    echo ""

    # ---- 1. Download Python ----
    if [ ! -f "$PYTHON_BIN" ]; then
        echo -e "  ${CYAN}↓${NC} Downloading Python $PYTHON_VERSION..."
        mkdir -p "$PYTHON_DIR"
        local fname="cpython-${PYTHON_VERSION}+${PYTHON_TAG}-${PY_PLATFORM_TAG}-install_only_stripped.tar.gz"
        local tmp; tmp="$(mktemp)"
        download_gh "$PYTHON_RELEASE_PATH/$fname" "$tmp"
        tar xzf "$tmp" -C "$PYTHON_DIR" --strip-components=1
        rm -f "$tmp"
        if [ ! -f "$PYTHON_BIN" ]; then
            echo -e "  ${RED}✗ Python download failed${NC}"
            read -p "  Press Enter to exit..."
            exit 1
        fi
        echo -e "  ${GREEN}✓${NC} Python downloaded"
    fi

    # Remove quarantine attribute (macOS Gatekeeper)
    if xattr -l "$PYTHON_BIN" 2>/dev/null | grep -q "com.apple.quarantine"; then
        xattr -rd com.apple.quarantine "$UHERMES_DIR" 2>/dev/null || true
    fi

    # ---- 2. Install hermes-agent ----
    if ! "$PYTHON_BIN" -c "import sys; sys.path.insert(0,'$PACKAGES_DIR'); import run_agent" 2>/dev/null; then
        echo -e "  ${CYAN}↓${NC} Installing hermes-agent from portable/agent (with PyPI deps)..."
        mkdir -p "$PACKAGES_DIR"
        pip_install_to_target "$UHERMES_DIR/agent"
        echo -e "  ${GREEN}✓${NC} hermes-agent installed"
    fi

    # ---- 3. Install webui deps ----
    if [ -f "$WEBUI_DIR/requirements.txt" ]; then
        echo -e "  ${CYAN}↓${NC} Installing webui PyPI dependencies..."
        pip_install_to_target -r "$WEBUI_DIR/requirements.txt"
        echo -e "  ${GREEN}✓${NC} webui deps installed"
    fi

    echo ""
    echo -e "  ${GREEN}[OK] Setup complete. Starting U-Hermes...${NC}"
    echo ""
}

if need_setup; then
    do_setup
fi

# ---- Sanity checks ----
if [ ! -f "$WEBUI_DIR/server.py" ]; then
    echo -e "  ${RED}Error: webui not found${NC}"
    read -p "  Press Enter to exit..."
    exit 1
fi
# Clear quarantine on every run (in case files were copied to a new Mac)
if xattr -l "$PYTHON_BIN" 2>/dev/null | grep -q "com.apple.quarantine"; then
    echo -e "  ${YELLOW}Removing macOS security restriction...${NC}"
    xattr -rd com.apple.quarantine "$UHERMES_DIR" 2>/dev/null || true
fi

PYTHON_VER=$("$PYTHON_BIN" --version)
echo -e "  Python: ${GREEN}${PYTHON_VER}${NC}"
echo ""

# ---- Init data directories ----
mkdir -p "$HERMES_HOME" "$DATA_DIR/logs"

# ---- Detect mount-path change since last run ----
PATH_MARKER="$HERMES_HOME/.last_path"
if [ -f "$PATH_MARKER" ]; then
    LAST_PATH=$(cat "$PATH_MARKER" 2>/dev/null)
    if [ -n "$LAST_PATH" ] && [ "$LAST_PATH" != "$UHERMES_DIR" ]; then
        echo -e "  ${YELLOW}[INFO] USB path changed since last run:${NC}"
        echo "         old: $LAST_PATH"
        echo "         new: $UHERMES_DIR"
        echo -e "  ${CYAN}Archiving old state to data/.hermes.bak ...${NC}"
        rm -rf "$DATA_DIR/.hermes.bak" 2>/dev/null
        mv "$HERMES_HOME" "$DATA_DIR/.hermes.bak" 2>/dev/null
        mkdir -p "$HERMES_HOME"
        echo -e "  ${GREEN}[OK] Fresh state directory created.${NC}"
        echo ""
    fi
fi
echo "$UHERMES_DIR" > "$PATH_MARKER"

# ---- Bootstrap API key (device fingerprint → .env) ----
echo -e "  ${CYAN}Binding device fingerprint...${NC}"
"$PYTHON_BIN" "$UHERMES_DIR/lib/bootstrap-api.py" "$HERMES_HOME" || true
echo ""

# ---- Environment (portable mode) ----
export HERMES_HOME="$HERMES_HOME"
export HERMES_WEBUI_STATE_DIR="$HERMES_HOME/webui"
export HERMES_WEBUI_HOST="127.0.0.1"
export HERMES_WEBUI_AGENT_DIR="$UHERMES_DIR/agent"
export HERMES_WEBUI_PYTHON="$PYTHON_BIN"
export PYTHONPATH="$UHERMES_DIR/agent:$PACKAGES_DIR${PYTHONPATH:+:$PYTHONPATH}"
export PATH="$PYTHON_DIR/bin:$PATH"
export HERMES_WEBUI_DEFAULT_WORKSPACE="$UHERMES_DIR/workspace"
mkdir -p "$HERMES_WEBUI_DEFAULT_WORKSPACE"

# ---- Find available port ----
PORT=${HERMES_WEBUI_PORT:-8787}
while lsof -i :$PORT >/dev/null 2>&1; do
    echo -e "  ${YELLOW}Port $PORT in use, trying next...${NC}"
    PORT=$((PORT + 1))
    if [ $PORT -gt 8799 ]; then
        echo -e "  ${RED}No available port (8787-8799)${NC}"
        read -p "  Press Enter to exit..."
        exit 1
    fi
done
export HERMES_WEBUI_PORT="$PORT"

# ---- Auto-launch messaging gateway in background if configured ----
if [ -f "$HERMES_HOME/.env" ] && grep -q '^FEISHU_APP_ID=' "$HERMES_HOME/.env"; then
    echo -e "  ${CYAN}Starting messaging gateway in background (log: data/logs/gateway.log)...${NC}"
    mkdir -p "$DATA_DIR/logs"
    (
        cd "$UHERMES_DIR/agent" && \
        HERMES_HOME="$HERMES_HOME" \
        PYTHONPATH="$UHERMES_DIR/agent:$PACKAGES_DIR" \
        PYTHONIOENCODING=utf-8 \
        "$PYTHON_BIN" -m gateway.run --verbose \
            >"$DATA_DIR/logs/gateway.log" 2>&1 &
    )
fi

# ---- Start webui ----
echo -e "  ${CYAN}Starting Hermes on port $PORT...${NC}"
echo ""

cd "$WEBUI_DIR"
"$PYTHON_BIN" bootstrap.py --no-browser --skip-agent-install "$PORT" &
WEBUI_PID=$!

# ---- Wait for server, then open browser ----
for i in $(seq 1 30); do
    sleep 0.5
    if curl -s -o /dev/null "http://127.0.0.1:$PORT/" 2>/dev/null; then
        open "http://127.0.0.1:$PORT/" 2>/dev/null || true
        break
    fi
done

echo -e "  ${GREEN}════════════════════════════════${NC}"
echo -e "  ${GREEN}⚕ U-Hermes is running!${NC}"
echo -e "  ${GREEN}   Web UI: http://127.0.0.1:$PORT/${NC}"
echo ""
echo -e "  ${YELLOW}Press Ctrl+C to stop${NC}"
echo -e "  ${GREEN}════════════════════════════════${NC}"
echo ""

cleanup() {
    kill $WEBUI_PID 2>/dev/null
    echo ""
    echo "  ⚕ U-Hermes stopped."
    exit 0
}
trap cleanup INT TERM
wait $WEBUI_PID
