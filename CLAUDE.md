# CLAUDE.md

## Project Overview — CRITICAL MENTAL MODEL

**This repo IS the USB drive content**, minus large dependencies. The relationship:

```
代码库（git）= U 盘骨架（脚本 + webui 源码）
     ↓ bash setup.sh
完整文件夹 = U 盘内容（骨架 + Python 运行时 + hermes-agent）
     ↓ 拷贝到 U 盘
U 盘 = 插上就能用
```

The repo is NOT a "build tool" — it IS the USB structure. `setup.sh` only fills in large deps (standalone Python binary + hermes-agent pip packages) that can't go in git. After `setup.sh`, the `portable/` folder is directly copyable to a USB drive.

## Development Commands

```bash
cd portable && bash setup.sh           # Download Python + hermes-agent into app/
bash Mac-Start.command                 # Launch (macOS)
cp -R portable/ /Volumes/USB/U-Hermes/ # Copy to USB
```

## Architecture

```
portable/
  setup.sh              ← One-time: download standalone Python + pip install hermes-agent
  Mac-Start.command      ← Double-click to launch on Mac
  webui/                 ← Web UI source (IN REPO, from hermes-webui upstream)
    server.py, bootstrap.py, api/, static/
  app/                   ← Downloaded by setup.sh, NOT in git
    runtime/python-mac-arm64/  ← Standalone Python binary (relocatable)
    packages/                  ← hermes-agent + all pip deps (--target, no venv)
  data/.hermes/          ← Runtime state (NOT in git)
```

Key design: no venv. Python is a standalone relocatable binary; packages are installed
via `pip install --target app/packages/` and loaded via `PYTHONPATH`. This means the
entire `portable/` directory can be moved to any Mac and it still works.

## What NOT to Commit

- `portable/app/` (Python runtime + installed packages)
- `portable/data/` (runtime state)
