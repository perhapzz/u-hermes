# CLAUDE.md

## Project Overview — CRITICAL MENTAL MODEL

**This repo IS the USB drive content**, minus large dependencies. The relationship:

```
代码库（git）= U 盘骨架（脚本 + webui 源码）
     ↓ Start.command / Start.bat (首次自动 setup)
完整文件夹 = U 盘内容（骨架 + Python 运行时 + hermes-agent）
     ↓ 拷贝到 U 盘
U 盘 = 插上就能用
```

The repo is NOT a "build tool" — it IS the USB structure. The unified `Start.*` launchers detect missing deps on first run and download standalone Python + hermes-agent into `portable/app/` automatically; subsequent runs skip straight to launch. After the first run, the entire directory is directly copyable to a USB drive.

## Development Commands

```bash
bash Start.command                  # Launch (macOS) — first run auto-installs
# Or on Windows: double-click Start.bat
cp -R . /Volumes/USB/U-Hermes/      # Copy whole repo to USB
```

## Architecture

```
u-hermes/                  ← USB root (launchers live here for user UX)
  Start.command            ← Mac launcher (first run = setup + launch; later = launch)
  Start.bat                ← Windows launcher (same all-in-one behavior)
  portable/                ← USB skeleton internals (everything below)
    webui/                 ← Web UI source (IN REPO, from hermes-webui upstream)
      server.py, bootstrap.py, api/, static/
    agent/                 ← hermes-agent source (IN REPO)
    app/                   ← Downloaded by setup.sh, NOT in git
      runtime/python-mac-arm64/  ← Standalone Python binary (relocatable)
      packages/                  ← hermes-agent + all pip deps (--target, no venv)
    data/.hermes/          ← Runtime state (NOT in git)
```

The launchers at the repo root just compute `UHERMES_DIR = <launcher dir>/portable`
and delegate to the same logic that used to live inside portable/. This keeps the
USB user experience clean (3 scripts at root) without flattening the whole tree.

Key design: no venv. Python is a standalone relocatable binary; packages are installed
via `pip install --target app/packages/` and loaded via `PYTHONPATH`. This means the
entire `portable/` directory can be moved to any Mac and it still works.

## What NOT to Commit

- `portable/app/` (Python runtime + installed packages)
- `portable/data/` (runtime state)
- `portable/workspace/` (agent's test artifacts)
