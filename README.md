# ⚕ U-Hermes

> **把 Hermes AI Agent 做成 U 盘 — 插上就能用**

参考 [U-Claw](https://github.com/dongsheng123132/u-claw) 的模式，将 [hermes-agent](https://github.com/NousResearch/hermes-agent) + [hermes-webui](https://github.com/NousResearch/hermes-webui) 打包成便携版。

## 快速开始

```bash
# 1. 克隆
git clone <this-repo> u-hermes

# 2. 安装依赖（下载 standalone Python + hermes-agent，无需系统 Python）
cd u-hermes
bash setup.sh           # Mac
# 或双击 setup.bat      # Windows

# 3. 启动
bash Mac-Start.command   # Mac
# 或双击 Windows-Start.bat  # Windows

# 4. 拷贝到 U 盘（整个 u-hermes 目录就是 U 盘内容）
cp -R . /Volumes/YOUR_USB/U-Hermes/
```

## 文件结构

```
u-hermes/                       # = U 盘根目录
├── setup.sh / setup.bat       # 一键搭建：下载 Python 运行时 + hermes-agent
├── Mac-Start.command          # macOS 双击启动
├── Windows-Start.bat          # Windows 双击启动
└── portable/                   # USB 骨架内部细节
    ├── webui/                 # Web UI 源码（在 repo 里）
    │   ├── server.py, bootstrap.py
    │   ├── api/
    │   └── static/
    ├── agent/                 # hermes-agent 源码（在 repo 里）
    ├── app/                   # setup 下载的内容（不在 git 里）
    │   ├── runtime/
    │   │   ├── python-mac-arm64/  # Standalone Python (Mac ARM64)
    │   │   ├── python-mac-x64/    # Standalone Python (Mac Intel)
    │   │   └── python-win-x64/    # Standalone Python (Windows)
    │   └── packages/          # hermes-agent + pip 依赖 (--target)
    └── data/
        └── .hermes/           # 运行时数据
```

## 平台支持

| 功能 | Mac (ARM64) | Mac (x64) | Windows x64 |
|------|-------------|-----------|-------------|
| **免安装运行** | `Mac-Start.command` | `Mac-Start.command` | `Windows-Start.bat` |
| **搭建** | `bash setup.sh` | `bash setup.sh` | `setup.bat` |
| **跨平台 U 盘** | `bash setup.sh --all-platforms` | — | — |

## 设计原则

- **和 U-Claw 相同的架构**：repo = U 盘骨架，setup 只补大依赖
- **无 venv**：用 standalone Python 二进制 + `pip install --target` + `PYTHONPATH`，全部相对路径，换机器不会坏
- **零系统依赖**：不需要系统装 Python/pip/uv，standalone Python 自带 pip
