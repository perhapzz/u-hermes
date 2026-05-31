# U-Hermes 消息平台接入指南

让 U-Hermes 在 **飞书** 和 **微信（个人号）** 上像聊天机器人一样工作。

> ⚠️ 个人微信账号存在被封风险（违反腾讯协议），仅建议使用 **小号** 测试。
> 飞书使用官方开放平台，安全合规。

---

## 一、整体步骤

1. 至少先成功跑过一次 `Windows-Start.bat` / `Mac-Start.command`，确保 `portable/app/` 已经下载好运行时。
2. 打开 WebUI（默认 <http://127.0.0.1:8787>）→ Settings → **Messaging Gateway**，填写飞书 / 微信凭证后保存。
   - 也可以手动编辑 `portable/data/.hermes/.env` + `portable/data/.hermes/config.yaml`（参考 `docs/config.example.yaml`）。
3. 在飞书板块点 **测试连通性**，机器人收到测试消息即代表配置 OK。
4. 关闭 Start 启动窗口 → 重新双击 `Windows-Start.bat` / `Mac-Start.command`。WebUI 与网关会同时在后台启动（网关日志在 `portable/data/logs/gateway.log`）。
5. 在对应 App 里给机器人发消息，确认能正常对话。

> webui 与 gateway 是两个独立进程，可以同时运行。

---

## 二、飞书（推荐）

### 1. 在飞书开放平台创建自建应用

进入 <https://open.feishu.cn/app>，点击 **创建企业自建应用**。

记录三项关键信息：
- `App ID`（形如 `cli_xxxxxxxxxxxxxxxx`）
- `App Secret`
- 应用所在的 **租户域名**（`feishu` 或 `lark`）

### 2. 开通权限

在 **权限管理** 中至少开通：
- `im:message`（接收/发送消息）
- `im:message:send_as_bot`
- `im:chat`（获取群聊列表）
- `contact:user.base:readonly`（获取发送者昵称，可选）

### 3. 选择连接模式

| 模式 | 适合 | 配置 |
|------|------|------|
| **websocket（推荐）** | 个人 / 小团队，无公网 | 仅需 `app_id` + `app_secret` |
| webhook | 已有公网域名 / frp | 还需在飞书后台配置回调 URL，并填 `verification_token` 和 `encrypt_key` |

### 4. 填 config.yaml

```yaml
platforms:
  feishu:
    enabled: true
    extra:
      app_id: "cli_xxxxxxxxxxxxxxxx"
      app_secret: "your-app-secret"
      connection_mode: "websocket"
```

### 5. 发布应用

在 **版本管理与发布** 提交版本，等管理员审核通过后，把机器人 **添加到群** 或 **直接私聊** 即可。

---

## 三、微信（个人号 · iLink 协议）

### 1. 配置开关

把 `config.yaml` 中：

```yaml
weixin:
  enabled: true
  extra:
    account_id: ""
```

### 2. 首次扫码登录

启动 gateway 后，会在终端打印一个 **二维码 URL**（同时直接渲染二维码）。

用 **小号微信** 扫码 → 在手机上点击 **登录** → 终端显示 `login success`。

登录信息会自动持久化到 `portable/data/.hermes/weixin/<account_id>.json`，下次启动直接复用，不需要再扫码。

### 3. 控制谁能用

```yaml
weixin:
  extra:
    dm_policy: "allowlist"          # 私聊只接受白名单
    # 在 .env 里维护 WEIXIN_ALLOWED_USERS=wxid_aaa,wxid_bbb
    group_policy: "disabled"        # 默认关闭群聊
```

### 4. 风险提示

- 个人号属于灰产协议，**请勿在主号上跑**。
- 短时间内回复过多消息可能触发风控（10 分钟 100+ 条）。
- 内置已有 `send_chunk_delay_seconds` 节流（默认 1.5 秒/条）。

---

## 四、环境变量（.env，可选）

`config.yaml` 适合静态配置，敏感字段或临时切换可写入 `portable/data/.hermes/.env`：

```
FEISHU_APP_SECRET=xxxxxxxx
FEISHU_ALLOWED_USERS=ou_aaa,ou_bbb
WEIXIN_ALLOWED_USERS=wxid_aaa,wxid_bbb
```

`.env` 优先级 **高于** `config.yaml`。

---

## 五、常见问题

**Q：webui 和 gateway 必须同时开吗？**
A：不必。webui 是配置面板，gateway 才是消息桥。常见用法：第一次用 webui 配好模型 → 之后只开 gateway。

**Q：模型在哪配？**
A：webui 里 (`http://127.0.0.1:8787/`) 配好的模型/凭证会被 gateway 自动复用（共用 `HERMES_HOME`）。

**Q：可以同时跑飞书 + 微信吗？**
A：可以。两个都 `enabled: true` 即可，单进程多平台。

**Q：日志在哪？**
A：`portable/data/logs/`。启动时加 `--verbose` 已经默认开了。

**Q：怎么停？**
A：Gateway 终端里按 `Ctrl+C`，或直接关窗口。
