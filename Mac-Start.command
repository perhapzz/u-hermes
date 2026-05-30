#!/bin/bash
# ============================================================
# U-Hermes - Portable AI Agent (macOS)
# Double-click to start / 双击启动
# ============================================================

# Launcher lives at repo root; the portable USB skeleton is in portable/.
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

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo ""
echo -e "${CYAN}"
echo "  ╔══════════════════════════════════════╗"
echo "  ║     ⚕ U-Hermes v0.1                 ║"
echo "  ║     Portable AI Agent               ║"
echo "  ╚══════════════════════════════════════╝"
echo -e "${NC}"

# ---- 1. Detect CPU & set Python path ----
ARCH=$(uname -m)
if [ "$ARCH" = "arm64" ]; then
    PYTHON_DIR="$RUNTIME_DIR/python-mac-arm64"
    echo -e "  ${GREEN}Apple Silicon (M series)${NC}"
elif [ "$ARCH" = "x86_64" ]; then
    PYTHON_DIR="$RUNTIME_DIR/python-mac-x64"
    echo -e "  ${GREEN}Intel Mac (x64)${NC}"
else
    echo -e "  ${RED}Unsupported architecture: $ARCH${NC}"
    read -p "  Press Enter to exit..."
    exit 1
fi

PYTHON_BIN="$PYTHON_DIR/bin/python3"

# ---- 2. Remove macOS quarantine ----
if xattr -l "$PYTHON_BIN" 2>/dev/null | grep -q "com.apple.quarantine"; then
    echo -e "  ${YELLOW}Removing macOS security restriction...${NC}"
    xattr -rd com.apple.quarantine "$UHERMES_DIR" 2>/dev/null || true
    echo -e "  ${GREEN}Done${NC}"
fi

# ---- 3. Check runtime ----
if [ ! -f "$PYTHON_BIN" ]; then
    echo -e "  ${RED}Error: Python runtime not found${NC}"
    echo "  Please run: bash setup.sh"
    read -p "  Press Enter to exit..."
    exit 1
fi

if [ ! -f "$WEBUI_DIR/server.py" ]; then
    echo -e "  ${RED}Error: webui not found${NC}"
    read -p "  Press Enter to exit..."
    exit 1
fi

# ---- 3b. Check packages (fallback pip install if missing) ----
if ! "$PYTHON_BIN" -c "import sys; sys.path.insert(0,'$PACKAGES_DIR'); import run_agent" 2>/dev/null; then
    echo -e "  ${YELLOW}[WARN] packages not found${NC}"
    echo "  This release should ship with deps pre-installed."
    echo "  Falling back to pip install..."
    echo ""
    PIP_MIRROR="https://pypi.tuna.tsinghua.edu.cn/simple"
    PIP_EXTRA=""
    if curl -s --max-time 3 -o /dev/null "https://pypi.tuna.tsinghua.edu.cn/" 2>/dev/null; then
        if ! curl -s --max-time 3 -o /dev/null "https://pypi.org/" 2>/dev/null; then
            PIP_EXTRA="-i $PIP_MIRROR"
        fi
    fi
    mkdir -p "$PACKAGES_DIR"
    "$PYTHON_BIN" -m pip install "$UHERMES_DIR/agent" \
        --target "$PACKAGES_DIR" --no-user --disable-pip-version-check $PIP_EXTRA
    if [ -f "$WEBUI_DIR/requirements.txt" ]; then
        "$PYTHON_BIN" -m pip install -r "$WEBUI_DIR/requirements.txt" \
            --target "$PACKAGES_DIR" --no-user --disable-pip-version-check $PIP_EXTRA
    fi
    echo -e "  ${GREEN}Dependencies installed${NC}"
    echo ""
fi

PYTHON_VER=$("$PYTHON_BIN" --version)
echo -e "  Python: ${GREEN}${PYTHON_VER}${NC}"
echo ""

# ---- 4. Init data directories ----
mkdir -p "$HERMES_HOME" "$DATA_DIR/logs"

# ---- 4a. Detect mount-path change since last run ----
#    USB sticks mount at varying paths (/Volumes/USB1, /Volumes/Untitled, ...).
#    State files in data/.hermes may cache absolute paths from the previous
#    run; if the path changed, archive the old state so the agent starts
#    fresh instead of dereferencing dead paths.
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

# ---- 4b. Bootstrap API key (device fingerprint → .env) ----
echo -e "  ${CYAN}Binding device fingerprint...${NC}"
"$PYTHON_BIN" "$UHERMES_DIR/lib/bootstrap-api.py" "$HERMES_HOME" || true
echo ""

# ---- 5. Set environment (portable mode) ----
export HERMES_HOME="$HERMES_HOME"
export HERMES_WEBUI_STATE_DIR="$HERMES_HOME/webui"
export HERMES_WEBUI_HOST="127.0.0.1"
export HERMES_WEBUI_AGENT_DIR="$UHERMES_DIR/agent"
export HERMES_WEBUI_PYTHON="$PYTHON_BIN"
export PYTHONPATH="$PACKAGES_DIR:$UHERMES_DIR/agent${PYTHONPATH:+:$PYTHONPATH}"
export PATH="$PYTHON_DIR/bin:$PATH"

# ---- 5b. Portable workspace (USB-relative, no user home dependency) ----
export HERMES_WEBUI_DEFAULT_WORKSPACE="$UHERMES_DIR/workspace"
mkdir -p "$HERMES_WEBUI_DEFAULT_WORKSPACE"

# ---- 6. Find available port ----
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

# ---- 7. Start webui ----
echo -e "  ${CYAN}Starting Hermes on port $PORT...${NC}"
echo ""

cd "$WEBUI_DIR"
"$PYTHON_BIN" bootstrap.py --no-browser --skip-agent-install "$PORT" &
WEBUI_PID=$!

# ---- 8. Wait for server, then open browser ----
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

# ---- Cleanup on exit ----
cleanup() {
    kill $WEBUI_PID 2>/dev/null
    echo ""
    echo "  ⚕ U-Hermes stopped."
    exit 0
}
trap cleanup INT TERM

wait $WEBUI_PID
