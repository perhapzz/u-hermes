"""U-Hermes messaging gateway config (Feishu + Weixin).

Also exposes a connectivity test (POST /api/messaging-gateway/test-feishu)
that hits Feishu's tenant token + im/v1/messages endpoints directly using the
configured credentials. The test does NOT go through the running gateway
process; it independently proves that the app_id/app_secret + target are
valid and the network can reach open.feishu.cn / open.larksuite.com.


Storage rules (kept simple on purpose):
  - Feishu — everything in ``<HERMES_HOME>/.env`` as ``FEISHU_*`` env vars.
    The gateway already auto-enables Feishu when ``FEISHU_APP_ID`` +
    ``FEISHU_APP_SECRET`` are present (see gateway/config.py), so config.yaml
    does not need a ``platforms.feishu`` block at all.
  - Weixin — yaml ``platforms.weixin`` (with the third-party bridge URL etc.)
    plus ``WEIXIN_ALLOWED_USERS`` in ``.env``. The personal-Weixin path
    pre-dates the unified-env pattern and reads from yaml first.

Exposed via ``/api/messaging-gateway`` (GET/POST). The GET response masks
secrets so the page can render an "already configured" state without leaking
the value back to the browser; POST only updates a secret when a new
non-empty value is supplied.

Model provider / API key are intentionally NOT handled here — that lives in
the existing Settings → Providers tab.
"""
from __future__ import annotations

import os
from pathlib import Path
from typing import Any, Dict
import json as _json
import time as _time
import urllib.request as _ureq
import urllib.error as _uerr

from api.config import (
    _DEFAULT_HERMES_HOME,
    _load_yaml_config_file,
    _save_yaml_config_file,
)


def _hermes_home() -> Path:
    override = os.getenv("HERMES_HOME", "").strip()
    if override:
        return Path(override).expanduser().resolve()
    try:
        from api.profiles import get_active_hermes_home  # type: ignore

        return get_active_hermes_home()
    except Exception:
        return _DEFAULT_HERMES_HOME


def _config_path() -> Path:
    explicit = os.getenv("HERMES_CONFIG_PATH", "").strip()
    if explicit:
        return Path(explicit).expanduser().resolve()
    return _hermes_home() / "config.yaml"


def _env_path() -> Path:
    return _hermes_home() / ".env"


def _read_env_file(path: Path) -> Dict[str, str]:
    if not path.exists():
        return {}
    out: Dict[str, str] = {}
    try:
        for line in path.read_text(encoding="utf-8").splitlines():
            s = line.strip()
            if not s or s.startswith("#") or "=" not in s:
                continue
            k, v = s.split("=", 1)
            v = v.strip()
            if (v.startswith('"') and v.endswith('"')) or (
                v.startswith("'") and v.endswith("'")
            ):
                v = v[1:-1]
            out[k.strip()] = v
    except OSError:
        return {}
    return out


def _write_env_file(path: Path, env: Dict[str, str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = [f"{k}={v}" for k, v in env.items() if v not in (None, "")]
    path.write_text("\n".join(lines) + ("\n" if lines else ""), encoding="utf-8")


def _mask(value: str) -> str:
    if not value:
        return ""
    if len(value) <= 8:
        return "•" * len(value)
    return value[:4] + "•" * (len(value) - 8) + value[-4:]


def get_messaging_gateway_config() -> Dict[str, Any]:
    cfg = _load_yaml_config_file(_config_path())
    if not isinstance(cfg, dict):
        cfg = {}
    env = _read_env_file(_env_path())

    platforms = cfg.get("platforms") or {}
    weixin = platforms.get("weixin") or {}
    weixin_extra = weixin.get("extra") or {}

    feishu_app_id = env.get("FEISHU_APP_ID", "")
    feishu_app_secret = env.get("FEISHU_APP_SECRET", "")

    return {
        "feishu": {
            # "Enabled" = both creds present. The gateway derives the same fact.
            "enabled": bool(feishu_app_id and feishu_app_secret),
            "app_id": feishu_app_id,
            "app_secret_set": bool(feishu_app_secret),
            "app_secret_masked": _mask(feishu_app_secret),
            "connection_mode": env.get("FEISHU_CONNECTION_MODE", "websocket") or "websocket",
            "allowed_users": env.get("FEISHU_ALLOWED_USERS", ""),
            "home_channel": env.get("FEISHU_HOME_CHANNEL", ""),
        },
        "weixin": {
            "enabled": bool(weixin.get("enabled", False)),
            "account_id": str(weixin_extra.get("account_id", "") or ""),
            "base_url": str(weixin_extra.get("base_url", "") or ""),
            "allowed_users": env.get("WEIXIN_ALLOWED_USERS", ""),
        },
        "paths": {"config": str(_config_path()), "env": str(_env_path())},
    }


def _apply_env(env: Dict[str, str], key: str, value: str, *, clear_if_empty: bool) -> None:
    v = (value or "").strip()
    if v:
        env[key] = v
    elif clear_if_empty:
        env.pop(key, None)


def save_messaging_gateway_config(body: Any) -> Dict[str, Any]:
    if not isinstance(body, dict):
        raise ValueError("invalid request body")

    cfg_path = _config_path()
    cfg = _load_yaml_config_file(cfg_path)
    if not isinstance(cfg, dict):
        cfg = {}
    env_path = _env_path()
    env = _read_env_file(env_path)

    # ── Feishu (env-only) ────────────────────────────────────────────────
    f_in = body.get("feishu")
    if isinstance(f_in, dict):
        enabled = bool(f_in.get("enabled"))
        if "app_id" in f_in:
            _apply_env(env, "FEISHU_APP_ID", str(f_in.get("app_id") or ""), clear_if_empty=True)
        secret_in = f_in.get("app_secret")
        if isinstance(secret_in, str) and secret_in.strip():
            env["FEISHU_APP_SECRET"] = secret_in.strip()
        if "connection_mode" in f_in:
            cm = str(f_in.get("connection_mode") or "websocket").strip().lower()
            env["FEISHU_CONNECTION_MODE"] = cm if cm in {"websocket", "webhook"} else "websocket"
        if "allowed_users" in f_in:
            _apply_env(env, "FEISHU_ALLOWED_USERS",
                       str(f_in.get("allowed_users") or ""), clear_if_empty=True)
        if "home_channel" in f_in:
            _apply_env(env, "FEISHU_HOME_CHANNEL",
                       str(f_in.get("home_channel") or ""), clear_if_empty=True)
        # If disabled explicitly, wipe the credentials so the gateway stops
        # auto-enabling on next start. (allowed_users / home_channel kept so
        # toggling back on doesn't lose the allowlist.)
        if not enabled and "enabled" in f_in:
            env.pop("FEISHU_APP_ID", None)
            env.pop("FEISHU_APP_SECRET", None)
        # Drop any stale yaml block to avoid the two sources fighting.
        platforms = cfg.get("platforms")
        if isinstance(platforms, dict) and "feishu" in platforms:
            platforms.pop("feishu", None)
            if not platforms:
                cfg.pop("platforms", None)
            else:
                cfg["platforms"] = platforms

    # ── Weixin (yaml + WEIXIN_ALLOWED_USERS env) ─────────────────────────
    w_in = body.get("weixin")
    if isinstance(w_in, dict):
        platforms = cfg.get("platforms") or {}
        if not isinstance(platforms, dict):
            platforms = {}
        weixin = platforms.get("weixin") or {}
        if not isinstance(weixin, dict):
            weixin = {}
        weixin["enabled"] = bool(w_in.get("enabled"))
        extra = weixin.get("extra") or {}
        if not isinstance(extra, dict):
            extra = {}
        for key in ("account_id", "base_url"):
            if key in w_in:
                v = str(w_in.get(key) or "").strip()
                if v:
                    extra[key] = v
                else:
                    extra.pop(key, None)
        weixin["extra"] = extra
        platforms["weixin"] = weixin
        cfg["platforms"] = platforms
        if "allowed_users" in w_in:
            _apply_env(env, "WEIXIN_ALLOWED_USERS",
                       str(w_in.get("allowed_users") or ""), clear_if_empty=True)

    _save_yaml_config_file(cfg_path, cfg)
    _write_env_file(env_path, env)

    return get_messaging_gateway_config()


# ─────────────────────────────────────────────────────────────────────────────
# Connectivity test — POST /api/messaging-gateway/test-feishu
# ─────────────────────────────────────────────────────────────────────────────

_FEISHU_HOSTS = {
    "feishu":    "https://open.feishu.cn",
    "lark":      "https://open.larksuite.com",
}


def _http_post_json(url: str, payload: Dict[str, Any], headers: Dict[str, str] | None = None,
                    timeout: float = 10.0) -> Dict[str, Any]:
    data = _json.dumps(payload).encode("utf-8")
    req = _ureq.Request(url, data=data, method="POST")
    req.add_header("Content-Type", "application/json; charset=utf-8")
    for k, v in (headers or {}).items():
        req.add_header(k, v)
    try:
        with _ureq.urlopen(req, timeout=timeout) as resp:
            body = resp.read().decode("utf-8", errors="replace")
    except _uerr.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace") if e.fp else ""
        try:
            return _json.loads(body) if body else {"code": e.code, "msg": e.reason}
        except Exception:
            return {"code": e.code, "msg": e.reason, "raw": body}
    except Exception as e:
        return {"code": -1, "msg": f"{type(e).__name__}: {e}"}
    try:
        return _json.loads(body) if body else {}
    except Exception:
        return {"code": -1, "msg": "non-json response", "raw": body}


def _detect_receive_id_type(target: str) -> str:
    """Heuristic for Feishu receive_id_type based on prefix."""
    t = target.strip()
    if t.startswith("ou_"):
        return "open_id"
    if t.startswith("on_"):
        return "union_id"
    if t.startswith("oc_"):
        return "chat_id"
    if "@" in t:
        return "email"
    # Bare user IDs (no prefix) like the user's "a2cfee6b" — treat as user_id.
    return "user_id"


def test_feishu_connectivity(body: Any) -> Dict[str, Any]:
    """Send a one-shot test message via Feishu OpenAPI.

    Body (all optional):
      - target: receive_id (defaults to FEISHU_HOME_CHANNEL or first
        FEISHU_ALLOWED_USERS entry).
      - receive_id_type: "open_id" / "user_id" / "chat_id" / "email" /
        "union_id" (auto-detected from target prefix when omitted).
      - text: message text (defaults to a timestamped greeting).
      - host: "feishu" (default) or "lark".
    """
    env = _read_env_file(_env_path())
    # Also honor live process env so the test agrees with a running gateway.
    app_id = (env.get("FEISHU_APP_ID") or os.getenv("FEISHU_APP_ID") or "").strip()
    app_secret = (env.get("FEISHU_APP_SECRET") or os.getenv("FEISHU_APP_SECRET") or "").strip()
    if not app_id or not app_secret:
        return {"ok": False, "stage": "config",
                "error": "FEISHU_APP_ID / FEISHU_APP_SECRET 未配置。"}

    body = body if isinstance(body, dict) else {}
    target = str(body.get("target") or "").strip()
    if not target:
        target = (env.get("FEISHU_HOME_CHANNEL")
                  or os.getenv("FEISHU_HOME_CHANNEL") or "").strip()
    if not target:
        allowed = (env.get("FEISHU_ALLOWED_USERS")
                   or os.getenv("FEISHU_ALLOWED_USERS") or "").strip()
        if allowed:
            target = allowed.split(",")[0].strip()
    if not target:
        return {"ok": False, "stage": "config",
                "error": "未指定目标 (target)，且 FEISHU_HOME_CHANNEL / FEISHU_ALLOWED_USERS 都为空。"}

    receive_id_type = str(body.get("receive_id_type") or "").strip() or _detect_receive_id_type(target)
    host_key = str(body.get("host") or "feishu").strip().lower()
    host = _FEISHU_HOSTS.get(host_key, _FEISHU_HOSTS["feishu"])

    text = str(body.get("text") or "").strip()
    if not text:
        ts = _time.strftime("%Y-%m-%d %H:%M:%S")
        text = f"✅ U-Hermes 连通性测试 @ {ts}"

    # Step 1: tenant access token
    token_resp = _http_post_json(
        f"{host}/open-apis/auth/v3/tenant_access_token/internal",
        {"app_id": app_id, "app_secret": app_secret},
    )
    token = (token_resp or {}).get("tenant_access_token") or ""
    if not token:
        return {
            "ok": False, "stage": "tenant_access_token",
            "error": (token_resp or {}).get("msg") or "获取 tenant_access_token 失败",
            "code": (token_resp or {}).get("code"),
            "raw": token_resp,
        }

    # Step 2: send message
    payload = {
        "receive_id": target,
        "msg_type": "text",
        "content": _json.dumps({"text": text}, ensure_ascii=False),
    }
    send_resp = _http_post_json(
        f"{host}/open-apis/im/v1/messages?receive_id_type={receive_id_type}",
        payload,
        headers={"Authorization": f"Bearer {token}"},
    )
    code = (send_resp or {}).get("code")
    if code != 0:
        return {
            "ok": False, "stage": "send",
            "error": (send_resp or {}).get("msg") or "发送消息失败",
            "code": code,
            "target": target, "receive_id_type": receive_id_type,
            "raw": send_resp,
        }

    msg_id = (((send_resp or {}).get("data") or {}).get("message_id")) or ""
    return {
        "ok": True,
        "target": target,
        "receive_id_type": receive_id_type,
        "host": host,
        "message_id": msg_id,
        "text": text,
    }
