#!/usr/bin/env python3
"""
U-Hermes device fingerprint + API key bootstrap.

Generates a device-bound API key from hardware fingerprint and writes it
to the Hermes .env file. Idempotent: if key already exists and matches,
does nothing. Never overwrites a user-configured key.

Modeled after u-claw's bootstrap-xiapan.mjs + fingerprint.mjs.
"""

import hashlib
import os
import platform
import secrets
import subprocess
import sys
from pathlib import Path

API_BASE_URL = "https://ctrigger.com/v1"
DEFAULT_MODEL = "deepseek-v4-flash"

# ---------------------------------------------------------------------------
# Fingerprint
# ---------------------------------------------------------------------------

def _sha256(s: str) -> str:
    return hashlib.sha256(s.encode()).hexdigest()


def _run_cmd(cmd: list[str]) -> str:
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
        return r.stdout.strip() if r.returncode == 0 else ""
    except Exception:
        return ""


def _mac_fingerprint() -> tuple[str, str] | None:
    hw = _run_cmd(["/usr/sbin/system_profiler", "SPHardwareDataType"])
    hw_uuid = ""
    for line in hw.splitlines():
        if "Hardware UUID:" in line:
            hw_uuid = line.split(":")[-1].strip().upper()
            break

    disk = _run_cmd(["/usr/sbin/diskutil", "info", "/"])
    vol_uuid = ""
    for line in disk.splitlines():
        if "Volume UUID:" in line:
            vol_uuid = line.split(":")[-1].strip().upper()
            break

    if not hw_uuid and not vol_uuid:
        return None
    return ("mac", _sha256(f"MAC:{hw_uuid}:{vol_uuid}"))


def _linux_fingerprint() -> tuple[str, str] | None:
    machine_id = ""
    for path in ("/etc/machine-id", "/var/lib/dbus/machine-id"):
        try:
            machine_id = Path(path).read_text().strip()
            if machine_id:
                break
        except Exception:
            pass

    root_serial = ""
    out = _run_cmd(["/bin/lsblk", "-no", "SERIAL,MOUNTPOINT"])
    for line in out.splitlines():
        parts = line.strip().split()
        if len(parts) >= 2 and parts[1] == "/":
            root_serial = parts[0]
            break

    if not machine_id and not root_serial:
        return None
    return ("linux", _sha256(f"LINUX:{machine_id}:{root_serial}"))


def _seed_fingerprint(data_dir: Path) -> tuple[str, str]:
    seed_path = data_dir / ".usb_seed"
    if seed_path.exists():
        seed = seed_path.read_text().strip()
        if len(seed) == 64:
            return ("seed", seed)
    seed = secrets.token_hex(32)
    seed_path.parent.mkdir(parents=True, exist_ok=True)
    seed_path.write_text(seed + "\n")
    return ("seed", seed)


def get_fingerprint(data_dir: Path) -> tuple[str, str]:
    """Returns (source, fingerprint_hex)."""
    plat = platform.system()
    if plat == "Darwin":
        r = _mac_fingerprint()
        if r:
            return r
    elif plat == "Linux":
        r = _linux_fingerprint()
        if r:
            return r
    return _seed_fingerprint(data_dir)


# ---------------------------------------------------------------------------
# .env bootstrap
# ---------------------------------------------------------------------------

def _read_env(env_path: Path) -> dict[str, str]:
    """Parse a simple KEY=VALUE .env file."""
    result = {}
    if not env_path.exists():
        return result
    for line in env_path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        k = k.strip()
        if k.startswith("export "):
            k = k[7:].strip()
        v = v.strip().strip('"').strip("'")
        result[k] = v
    return result


def _write_env(env_path: Path, data: dict[str, str]) -> None:
    lines = []
    for k, v in data.items():
        lines.append(f"{k}={v}")
    env_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def bootstrap(hermes_home: Path) -> dict:
    """Generate device-bound API key and write to .env if needed.

    Writes ``CTRIGGER_API_KEY`` (+ ``CTRIGGER_BASE_URL`` and
    ``HERMES_DEFAULT_MODEL`` defaults) on first run. Older builds used
    ``OPENAI_API_KEY`` / ``OPENAI_BASE_URL`` for the same purpose; those
    stale entries are removed here when they match the fingerprint pattern
    or our ctrigger base URL so the Settings → Providers panel doesn't show
    a phantom key the user can't get rid of.
    """
    env_path = hermes_home / ".env"
    env = _read_env(env_path)

    source, fingerprint = get_fingerprint(hermes_home.parent)
    api_key = f"sk-{fingerprint}"

    # ---- One-time migration: drop legacy OPENAI_* seeded by previous builds.
    # Only purge values that look like our fingerprint key or ctrigger base URL;
    # if the user has their own real OpenAI creds we leave them alone.
    changed = False
    legacy_key = env.get("OPENAI_API_KEY", "").strip()
    legacy_url = env.get("OPENAI_BASE_URL", "").strip()
    if legacy_url == API_BASE_URL or (legacy_key.startswith("sk-") and len(legacy_key) == 67):
        env.pop("OPENAI_API_KEY", None)
        env.pop("OPENAI_BASE_URL", None)
        changed = True

    existing_key = env.get("CTRIGGER_API_KEY", "").strip()

    if existing_key and existing_key != api_key:
        # User has configured their own key — don't touch it
        if changed:
            _write_env(env_path, env)
        return {
            "action": "kept",
            "source": source,
            "api_key": existing_key[:16] + "...",
        }

    if existing_key == api_key and not changed:
        # Already configured with same fingerprint and no legacy cleanup needed
        return {"action": "noop", "source": source}

    # Write or update
    env["CTRIGGER_API_KEY"] = api_key
    if "CTRIGGER_BASE_URL" not in env:
        env["CTRIGGER_BASE_URL"] = API_BASE_URL
    if "HERMES_DEFAULT_MODEL" not in env:
        env["HERMES_DEFAULT_MODEL"] = DEFAULT_MODEL
    _write_env(env_path, env)

    action = "updated" if existing_key else "created"
    return {
        "action": action,
        "source": source,
        "api_key": api_key[:16] + "...",
        "purged_legacy_openai": changed,
    }


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: bootstrap-api.py <hermes-home-dir>", file=sys.stderr)
        sys.exit(2)
    hermes_home = Path(sys.argv[1])
    hermes_home.mkdir(parents=True, exist_ok=True)
    result = bootstrap(hermes_home)
    import json
    print(json.dumps(result))
