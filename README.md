# ⚕ U-Hermes

> **把 Hermes AI Agent 做成 U 盘 — 插上就能用**

> **许可证**：本项目采用 [Business Source License 1.1](./LICENSE)。
> 个人学习、测试、评估等**非生产用途免费**；任何**商业用途需先获得作者授权**。
> 自 **2030-06-09** 起，本许可下发布的版本将自动转为 **GPL-2.0-or-later** 开源协议。

参考 [U-Claw](https://github.com/dongsheng123132/u-claw) 的模式，将 [hermes-agent](https://github.com/NousResearch/hermes-agent) + [hermes-webui](https://github.com/NousResearch/hermes-webui) 打包成便携版。

## 快速开始

```bash
# 1. 克隆
git clone <this-repo> u-hermes
cd u-hermes

# 2. 启动（首次自动下载 standalone Python + hermes-agent，之后秒开）
bash Mac-Start.command       # Mac（也可双击）
# 或双击 Windows-Start.bat       # Windows

# 3. 拷贝到 U 盘（整个 u-hermes 目录就是 U 盘内容）
cp -R . /Volumes/YOUR_USB/U-Hermes/
```

## 文件结构

```
u-hermes/                       # = U 盘根目录
├── Mac-Start.command              # macOS 双击启动（首次自动 setup）
├── Windows-Start.bat                  # Windows 双击启动（首次自动 setup）
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
| **一键启动** | `Mac-Start.command` | `Mac-Start.command` | `Windows-Start.bat` |

> 首次启动会自动下载 Python 运行时和依赖；之后所有运行都是直接启动。

## 许可证 / License

本项目采用 **Business Source License 1.1 (BSL 1.1)**，完整条款见 [LICENSE](./LICENSE)。

- ✅ **非生产用途免费**：个人使用、学习、评估、测试可免费使用、修改、再分发。
- ⚠️ **商业用途需授权**：任何生产环境使用，或由商业主体用于商业产品 / 服务的场景，
  须先向作者 **perhapzz** 取得单独的商业许可。
- 🕓 **到期自动开源**：自 **2030-06-09**（Change Date）起，在本许可下发布的对应版本
  将自动转为 **GPL-2.0-or-later** 协议。

商业授权与合作请通过 Gitee Issues 联系：
https://gitee.com/phzbbbbbbbb/u-hermes/issues

> 注意：BSL 不是 OSI 认可的开源协议，但到期后会自动转为开源。
> 本仓库打包的 `hermes-agent` / `hermes-webui` 等第三方组件各自保留其原始许可证。
> Start 启动器会自动启动 WebUI；若配置了飞书 / 微信凭证，消息网关也会在后台一起拉起。

## 接入飞书 / 微信

WebUI 之外，还可以让 Hermes 当做飞书 / 个人微信里的聊天机器人：

1. 跑过一次 `*-Start` 完成首次安装。
2. 打开 WebUI → Settings → Messaging Gateway，填写 App ID / Secret，点 **保存** 再点 **测试连通性**。
3. 关闭 Start 启动窗口、再双击 `Windows-Start.bat` / `Mac-Start.command` 重启，网关就会随 Start 一起在后台启动。

详见 [docs/messaging-gateway-setup.md](docs/messaging-gateway-setup.md)。

## 设计原则

- **和 U-Claw 相同的架构**：repo = U 盘骨架，setup 只补大依赖
- **无 venv**：用 standalone Python 二进制 + `pip install --target` + `PYTHONPATH`，全部相对路径，换机器不会坏
- **零系统依赖**：不需要系统装 Python/pip/uv，standalone Python 自带 pip
