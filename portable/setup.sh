#!/bin/bash
# ============================================================
# U-Hermes Portable — Setup Script
# Usage: bash setup.sh [--all-platforms]
# Downloads standalone Python + installs hermes-agent into app/
# The webui source is already in this repo under webui/
# China-friendly: GitHub downloads go through ghfast.top accelerator,
# pip uses npmmirror.com
# ============================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$SCRIPT_DIR/app"
RUNTIME_DIR="$APP_DIR/runtime"
PACKAGES_DIR="$APP_DIR/packages"

PYTHON_TAG="20260510"
PYTHON_VERSION="3.11.15"
# GitHub accelerator for China (falls back to raw GitHub)
GH_ACCEL="https://ghfast.top/"
GH_RAW="https://github.com/"
PYTHON_RELEASE_PATH="astral-sh/python-build-standalone/releases/download/$PYTHON_TAG"
PIP_MIRROR="https://pypi.tuna.tsinghua.edu.cn/simple"

GREEN='\033[0;32m'
CYAN='\033[0;36m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo ""
echo -e "${CYAN}╔══════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  ⚕ U-Hermes Portable Setup          ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════╝${NC}"
echo ""

OS=$(uname -s)
ARCH=$(uname -m)
ALL_PLATFORMS=false
[ "${1:-}" = "--all-platforms" ] && ALL_PLATFORMS=true

if [ "$OS" != "Darwin" ]; then
    echo -e "  ${RED}Currently macOS only. Windows please use setup.bat${NC}"
    exit 1
fi

echo -e "  System: ${GREEN}$OS $ARCH${NC}"

# ---- Detect China network ----
IN_CHINA=false
if curl -s --max-time 3 -o /dev/null "https://pypi.tuna.tsinghua.edu.cn/" 2>/dev/null; then
    if ! curl -s --max-time 3 -o /dev/null "https://github.com/" 2>/dev/null; then
        IN_CHINA=true
    fi
fi

if [ "$IN_CHINA" = "true" ]; then
    echo -e "  Network: ${YELLOW}China (using mirrors)${NC}"
else
    echo -e "  Network: ${GREEN}Direct${NC}"
fi
echo ""

# ---- Helper: download file with China fallback ----
download_gh() {
    local path="$1"
    local output="$2"

    if [ "$IN_CHINA" = "true" ]; then
        echo -e "    ${CYAN}trying ghfast.top mirror...${NC}"
        if curl -fSL --max-time 300 "${GH_ACCEL}${GH_RAW}${path}" -o "$output" 2>/dev/null; then
            return 0
        fi
        echo -e "    ${YELLOW}mirror failed, trying direct...${NC}"
    fi
    curl -fSL "${GH_RAW}${path}" -o "$output"
}

# ---- Helper: download standalone Python ----
download_python() {
    local platform_tag="$1"
    local dir_name="$2"
    local check_exe="$3"  # bin/python3 or python.exe
    local target="$RUNTIME_DIR/$dir_name"

    if [ -f "$target/$check_exe" ]; then
        echo -e "  ${GREEN}✓${NC} Python ($dir_name) already exists"
        return
    fi

    local filename="cpython-${PYTHON_VERSION}+${PYTHON_TAG}-${platform_tag}-install_only_stripped.tar.gz"
    local release_path="$PYTHON_RELEASE_PATH/$filename"
    echo -e "  ${CYAN}↓${NC} Downloading Python $PYTHON_VERSION ($dir_name)..."

    mkdir -p "$target"
    local tmpfile
    tmpfile="$(mktemp)"
    download_gh "$release_path" "$tmpfile"
    tar xzf "$tmpfile" -C "$target" --strip-components=1
    rm -f "$tmpfile"

    if [ -f "$target/$check_exe" ]; then
        echo -e "  ${GREEN}✓${NC} Python ($dir_name) downloaded"
    else
        echo -e "  ${RED}✗ Python download failed${NC}"
        exit 1
    fi
}

# ---- Helper: pip install with China mirror ----
pip_install() {
    if [ "$IN_CHINA" = "true" ]; then
        "$PYTHON_BIN" -m pip install "$@" \
            --target "$PACKAGES_DIR" \
            --no-user \
            --disable-pip-version-check \
            --quiet \
            -i "$PIP_MIRROR"
    else
        "$PYTHON_BIN" -m pip install "$@" \
            --target "$PACKAGES_DIR" \
            --no-user \
            --disable-pip-version-check \
            --quiet
    fi
}

# ---- 1. Download Python (current platform) ----
if [ "$ARCH" = "arm64" ]; then
    download_python "aarch64-apple-darwin" "python-mac-arm64" "bin/python3"
    PYTHON_BIN="$RUNTIME_DIR/python-mac-arm64/bin/python3"
else
    download_python "x86_64-apple-darwin" "python-mac-x64" "bin/python3"
    PYTHON_BIN="$RUNTIME_DIR/python-mac-x64/bin/python3"
fi

# ---- 1b. Download Python for other platforms (with --all-platforms) ----
if [ "$ALL_PLATFORMS" = "true" ]; then
    if [ "$ARCH" = "arm64" ]; then
        download_python "x86_64-apple-darwin" "python-mac-x64" "bin/python3"
    else
        download_python "aarch64-apple-darwin" "python-mac-arm64" "bin/python3"
    fi
    download_python "x86_64-pc-windows-msvc" "python-win-x64" "python.exe"
fi

# ---- 2. Install hermes-agent from local source ----
if [ -d "$PACKAGES_DIR" ] && "$PYTHON_BIN" -c "import sys; sys.path.insert(0,'$PACKAGES_DIR'); import run_agent" 2>/dev/null; then
    echo -e "  ${GREEN}✓${NC} hermes-agent already installed"
else
    echo -e "  ${CYAN}↓${NC} Installing hermes-agent..."
    mkdir -p "$PACKAGES_DIR"
    pip_install "$SCRIPT_DIR/agent"
    echo -e "  ${GREEN}✓${NC} hermes-agent installed"
fi

# ---- 3. Install webui dependencies into same packages dir ----
WEBUI_REQS="$SCRIPT_DIR/webui/requirements.txt"
if [ -f "$WEBUI_REQS" ]; then
    echo -e "  ${CYAN}↓${NC} Installing webui dependencies..."
    pip_install -r "$WEBUI_REQS"
    echo -e "  ${GREEN}✓${NC} webui deps installed"
fi

# ---- 4. Init data dirs ----
mkdir -p "$SCRIPT_DIR/data/.hermes" "$SCRIPT_DIR/data/logs"

# ---- Done ----
echo ""
echo -e "${GREEN}════════════════════════════════════════${NC}"
echo -e "${GREEN}  ✅ Setup complete!${NC}"
echo ""
echo -e "  Launch:"
echo -e "    Mac:     ${CYAN}bash Mac-Start.command${NC}"
echo -e "    Windows: double-click ${CYAN}Windows-Start.bat${NC}"
echo ""
echo -e "  Directory structure:"
echo -e "    webui/              ← Web UI source (in repo)"
echo -e "    app/runtime/        ← Python $PYTHON_VERSION"
echo -e "    app/packages/       ← hermes-agent + dependencies"
echo -e "    data/               ← Runtime state"
echo ""
echo -e "  ${CYAN}TIP: For cross-platform USB use: bash setup.sh --all-platforms${NC}"
echo -e "${GREEN}════════════════════════════════════════${NC}"
