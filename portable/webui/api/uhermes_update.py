"""
U-Hermes self-update from Gitee (or fallback GitHub).

Unlike ``api/updates.py`` (which expects ``portable/webui`` and ``portable/agent``
to be independent git checkouts of the upstream hermes-webui / hermes-agent
projects), the U-Hermes USB build vendors those two folders inside a single
parent repo: ``u-hermes`` itself.  So "update the webui" really means:

    1. ``cd`` to the U-Hermes repo root (the folder that contains ``portable/``
       and the ``*-Start`` launchers).
    2. Make sure a ``gitee`` remote pointing at the user's Gitee mirror exists.
    3. Fetch + hard-reset the current branch to ``gitee/<branch>``.
    4. Tell the user to close the window and re-run the launcher so the
       updated Python code is actually loaded.

When ``.git`` is missing (someone copied the folder to a USB drive without
git metadata), we fall back to a shallow clone into a temp directory and
copy the source tree on top of the running install — preserving
``portable/app``, ``portable/data``, and ``portable/workspace`` which hold
the downloaded Python runtime, persistent state, and agent scratch space.
"""
from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
import threading
from pathlib import Path

from api.config import REPO_ROOT, STREAMS, STREAMS_LOCK

# Default mirror; can be overridden per-request via the API body.
DEFAULT_GITEE_URL = "https://gitee.com/phzbbbbbbbb/u-hermes.git"
DEFAULT_GITHUB_URL = "https://github.com/perhapzz/u-hermes.git"

# Folders inside ``portable/`` we must NEVER overwrite on a fresh clone
# (they hold the downloaded Python runtime, user data, and workspace state).
_PROTECTED_PORTABLE_SUBDIRS = {"app", "data", "workspace"}

_apply_lock = threading.Lock()


def _uhermes_root() -> Path:
    """U-Hermes repo root = parent of ``portable/`` = grandparent of ``api/``."""
    # REPO_ROOT is ``…/portable/webui`` (set in api/config.py).
    return REPO_ROOT.parent.parent


def _find_git_binary() -> str | None:
    """Prefer the PortableGit bundled inside ``portable/app/runtime`` on Windows.

    The launcher (Windows-Start.bat) downloads PortableGit into
    ``portable/app/runtime/git-win-x64`` so end-users on USB sticks never
    need git on PATH.  We re-use the same binary here.  On macOS / Linux we
    just trust whatever ``git`` is in PATH.
    """
    root = _uhermes_root()
    candidates = [
        root / "portable" / "app" / "runtime" / "git-win-x64" / "bin" / "git.exe",
        root / "portable" / "app" / "runtime" / "git-win-x64" / "cmd" / "git.exe",
    ]
    for c in candidates:
        if c.exists():
            return str(c)
    return shutil.which("git")


def _git_env(*, no_prompt: bool = False) -> dict:
    """Build a clean environment for git subprocesses.

    - Strips GIT_DIR / GIT_WORK_TREE so git discovers the repo from ``cwd``
      (the Windows launcher used to export a bat var literally named GIT_DIR
      pointing at PortableGit, which git misread as the repo → "not a git
      repository").
    - When *no_prompt* is set, fully disables interactive auth so a private /
      rate-limited remote can NEVER pop a Git Credential Manager dialog or
      block on a terminal prompt. Read-only check operations use this so they
      either succeed anonymously or fail fast.
    """
    env = {
        k: v
        for k, v in os.environ.items()
        if k not in ("GIT_DIR", "GIT_WORK_TREE")
    }
    if no_prompt:
        env["GIT_TERMINAL_PROMPT"] = "0"   # never prompt on the terminal
        env["GCM_INTERACTIVE"] = "Never"   # Git Credential Manager: no GUI
        env["GIT_ASKPASS"] = ""            # disable any askpass helper
        env["SSH_ASKPASS"] = ""
    return env


def _run_git(args, cwd, *, git_bin: str, timeout: int = 60, no_prompt: bool = False):
    """Run a git command; return (combined output, ok)."""
    try:
        env = _git_env(no_prompt=no_prompt)
        run_args = [git_bin]
        if no_prompt:
            # Belt-and-suspenders: also neutralise any configured credential
            # helper for THIS invocation only (does not touch global config).
            run_args += ["-c", "credential.helper="]
        run_args += list(args)
        r = subprocess.run(
            run_args,
            cwd=str(cwd),
            capture_output=True,
            text=True,
            timeout=timeout,
            env=env,
        )
        out = (r.stdout or "").strip()
        err = (r.stderr or "").strip()
        if r.returncode == 0:
            return out or err, True
        return err or out or f"git exited with status {r.returncode}", False
    except subprocess.TimeoutExpired:
        return f"git {' '.join(args)} timed out after {timeout}s", False
    except FileNotFoundError:
        return "git executable not found", False
    except OSError as exc:
        return f"git failed to start: {exc}", False


def _current_branch(root: Path, git_bin: str) -> str:
    """Return the current branch, falling back to 'main' then 'master'."""
    out, ok = _run_git(["rev-parse", "--abbrev-ref", "HEAD"], root, git_bin=git_bin, timeout=10)
    if ok and out and out != "HEAD":
        return out
    # Detached HEAD or empty repo: probe remote
    for cand in ("main", "master"):
        _, ok2 = _run_git(["rev-parse", "--verify", f"refs/remotes/gitee/{cand}"], root, git_bin=git_bin, timeout=10)
        if ok2:
            return cand
    return "main"


def _ensure_gitee_remote(root: Path, git_bin: str, gitee_url: str) -> tuple[str, bool]:
    """Make sure a 'gitee' remote exists and points at the requested URL."""
    existing, ok = _run_git(["remote", "get-url", "gitee"], root, git_bin=git_bin, timeout=10)
    if ok and existing:
        if existing == gitee_url:
            return "remote 'gitee' already configured", True
        _, ok2 = _run_git(["remote", "set-url", "gitee", gitee_url], root, git_bin=git_bin, timeout=10)
        return ("remote 'gitee' URL updated", ok2)
    out, ok = _run_git(["remote", "add", "gitee", gitee_url], root, git_bin=git_bin, timeout=10)
    if ok:
        return "remote 'gitee' added", True
    return out or "failed to add 'gitee' remote", False


def _active_stream_count() -> int:
    with STREAMS_LOCK:
        return len(STREAMS)


def _update_in_place_via_git(root: Path, git_bin: str, gitee_url: str) -> dict:
    """In-place update of an existing git checkout."""
    msg, ok = _ensure_gitee_remote(root, git_bin, gitee_url)
    if not ok:
        return {"ok": False, "message": f"Could not configure Gitee remote: {msg}"}

    fetch_out, fetch_ok = _run_git(
        ["fetch", "gitee", "--tags", "--force", "--prune"], root, git_bin=git_bin, timeout=120
    )
    if not fetch_ok:
        return {
            "ok": False,
            "message": (
                f"Failed to fetch from Gitee ({gitee_url}). "
                f"Check your internet connection.\nDetails: {fetch_out[:300]}"
            ),
        }

    branch = _current_branch(root, git_bin)
    ref = f"gitee/{branch}"

    # Verify the remote ref actually exists before we destroy local state.
    _, ref_ok = _run_git(["rev-parse", "--verify", ref], root, git_bin=git_bin, timeout=10)
    if not ref_ok:
        return {
            "ok": False,
            "message": (
                f"Gitee mirror does not have branch '{branch}'. "
                "Push that branch to Gitee first, or switch branches locally."
            ),
        }

    # SHAs for the response (before / after) — purely informational.
    before_sha, _ = _run_git(["rev-parse", "--short", "HEAD"], root, git_bin=git_bin, timeout=10)
    target_sha, _ = _run_git(["rev-parse", "--short", ref], root, git_bin=git_bin, timeout=10)

    # Hard-reset to remote: simplest, most reliable for a USB user-facing button.
    # We explicitly do NOT preserve local edits — the USB build is meant to be
    # consumed read-only; if someone hacked on it locally they can use `git stash`
    # themselves before clicking the button.
    reset_out, reset_ok = _run_git(["reset", "--hard", ref], root, git_bin=git_bin, timeout=60)
    if not reset_ok:
        return {"ok": False, "message": f"git reset --hard {ref} failed: {reset_out[:300]}"}

    return {
        "ok": True,
        "message": "Update downloaded. Please close this window and re-launch U-Hermes to apply.",
        "branch": branch,
        "before_sha": before_sha or None,
        "after_sha": target_sha or None,
        "remote_url": gitee_url,
        "method": "git-reset",
        "restart_required": True,
    }


def _copy_tree_preserving_protected(src: Path, dst: Path) -> None:
    """Copy src/* over dst/*, but leave portable/{app,data,workspace}/ alone.

    We delete every top-level entry in ``dst`` that exists in ``src`` first
    (so removed-upstream files vanish), then copy from ``src``.  The
    exception is ``dst/portable/<protected>`` which we never touch.
    """
    # Special-case ``portable/`` — copy file-by-file so we can skip protected dirs.
    for entry in src.iterdir():
        if entry.name == ".git":
            continue  # bringing the cloned .git over would replace the real one
        target = dst / entry.name
        if entry.name == "portable" and entry.is_dir() and target.exists():
            _merge_portable_dir(entry, target)
            continue
        if target.exists():
            if target.is_dir() and not target.is_symlink():
                shutil.rmtree(target)
            else:
                target.unlink()
        if entry.is_dir():
            shutil.copytree(entry, target, symlinks=True)
        else:
            shutil.copy2(entry, target)


def _merge_portable_dir(src_portable: Path, dst_portable: Path) -> None:
    """Update portable/ contents but skip ``app/``, ``data/``, ``workspace/``."""
    for entry in src_portable.iterdir():
        if entry.name in _PROTECTED_PORTABLE_SUBDIRS:
            continue
        target = dst_portable / entry.name
        if target.exists():
            if target.is_dir() and not target.is_symlink():
                shutil.rmtree(target)
            else:
                target.unlink()
        if entry.is_dir():
            shutil.copytree(entry, target, symlinks=True)
        else:
            shutil.copy2(entry, target)


def _update_via_fresh_clone(root: Path, git_bin: str, gitee_url: str) -> dict:
    """Fallback path: no .git in root, so shallow-clone then copy on top."""
    branch_hint = "main"  # gitee default — could probe but adds a round trip
    with tempfile.TemporaryDirectory(prefix="uhermes-update-") as tmp:
        tmp_root = Path(tmp) / "src"
        out, ok = _run_git(
            ["clone", "--depth=1", gitee_url, str(tmp_root)],
            cwd=Path(tmp),
            git_bin=git_bin,
            timeout=300,
        )
        if not ok:
            return {
                "ok": False,
                "message": f"Failed to clone {gitee_url}: {out[:300]}",
            }
        sha, _ = _run_git(["rev-parse", "--short", "HEAD"], tmp_root, git_bin=git_bin, timeout=10)
        try:
            _copy_tree_preserving_protected(tmp_root, root)
        except Exception as exc:  # pragma: no cover - copy errors are best-effort
            return {"ok": False, "message": f"Failed to copy updated files into place: {exc}"}

    return {
        "ok": True,
        "message": "Update downloaded. Please close this window and re-launch U-Hermes to apply.",
        "branch": branch_hint,
        "before_sha": None,
        "after_sha": sha or None,
        "remote_url": gitee_url,
        "method": "clone-copy",
        "restart_required": True,
    }


def update_from_gitee(gitee_url: str | None = None) -> dict:
    """Public entry point — invoked by the WebUI button."""
    url = (gitee_url or os.environ.get("UHERMES_GITEE_URL") or DEFAULT_GITEE_URL).strip()
    if not url:
        return {"ok": False, "message": "No Gitee URL configured."}

    # Refuse while an agent stream is active — the same restart-class issue
    # the upstream apply_update() guards against.
    active = _active_stream_count()
    if active:
        plural = "s" if active != 1 else ""
        return {
            "ok": False,
            "message": (
                f"Cannot update while {active} active chat stream{plural} is running. "
                "Wait for the response to finish, then retry."
            ),
            "active_streams": active,
        }

    if not _apply_lock.acquire(blocking=False):
        return {"ok": False, "message": "An update is already in progress."}
    try:
        git_bin = _find_git_binary()
        if not git_bin:
            return {
                "ok": False,
                "message": (
                    "git executable not found. On Windows, re-run "
                    "Windows-Start.bat so PortableGit gets downloaded; on macOS/Linux, "
                    "install git via your package manager."
                ),
            }

        root = _uhermes_root()
        if not root.exists():
            return {"ok": False, "message": f"U-Hermes root not found: {root}"}

        if (root / ".git").exists():
            return _update_in_place_via_git(root, git_bin, url)
        return _update_via_fresh_clone(root, git_bin, url)
    finally:
        _apply_lock.release()


# ---------------------------------------------------------------------------
# Check-only: does Gitee have a newer commit than what we have locally?
# Used by the launcher / WebUI boot to show an "Update available" modal
# without actually downloading anything.
# ---------------------------------------------------------------------------

def _ls_remote_head(url: str, branch: str, git_bin: str, timeout: int = 15) -> str:
    """Return the full 40-char SHA of *branch* on the remote *url*, or ''."""
    try:
        r = subprocess.run(
            [git_bin, "-c", "credential.helper=", "ls-remote", "--heads", url, branch],
            capture_output=True,
            text=True,
            timeout=timeout,
            env=_git_env(no_prompt=True),
        )
        if r.returncode != 0:
            return ""
        # Output format: "<sha>\trefs/heads/<branch>"
        line = (r.stdout or "").strip().splitlines()
        if not line:
            return ""
        sha = line[0].split("\t", 1)[0].strip()
        return sha if len(sha) == 40 else ""
    except (subprocess.TimeoutExpired, OSError):
        return ""


def check_for_updates(gitee_url: str | None = None) -> dict:
    """Compare local HEAD to gitee/<branch> HEAD without modifying anything.

    Returns a dict with:
        ok            — bool, whether the check itself completed
        update_available — bool, True iff remote_sha != local_sha
        local_sha       — short SHA of local HEAD (or None)
        remote_sha      — short SHA of remote HEAD (or None)
        local_sha_full  — 40-char SHA (used by frontend skip logic)
        remote_sha_full — 40-char SHA (skip-this-version comparison key)
        branch          — branch name probed
        remote_url      — URL probed
        message         — human-readable status (only set on failure)
    """
    url = (gitee_url or os.environ.get("UHERMES_GITEE_URL") or DEFAULT_GITEE_URL).strip()
    if not url:
        return {"ok": False, "update_available": False, "message": "No Gitee URL configured."}

    git_bin = _find_git_binary()
    if not git_bin:
        return {
            "ok": False,
            "update_available": False,
            "message": "git executable not found; cannot check for updates.",
        }

    root = _uhermes_root()
    if not root.exists() or not (root / ".git").exists():
        # Non-git deployment — we have no local SHA to compare against.
        # The "Update from Gitee" button still works (clone-copy fallback),
        # so we just report that we can't tell.
        return {
            "ok": False,
            "update_available": False,
            "message": "Local install is not a git checkout; cannot detect updates.",
        }

    branch = _current_branch(root, git_bin)
    local_full, ok_local = _run_git(["rev-parse", "HEAD"], root, git_bin=git_bin, timeout=10)
    if not ok_local or len(local_full) != 40:
        return {
            "ok": False,
            "update_available": False,
            "message": "Could not resolve local HEAD.",
            "detail": str(local_full)[:300],
            "git_bin": git_bin,
            "root": str(root),
            "branch": branch,
        }

    remote_full = _ls_remote_head(url, branch, git_bin)
    if not remote_full:
        return {
            "ok": False,
            "update_available": False,
            "branch": branch,
            "remote_url": url,
            "message": f"Could not reach Gitee or branch '{branch}' missing on remote.",
        }

    return {
        "ok": True,
        "update_available": local_full != remote_full,
        "local_sha": local_full[:7],
        "remote_sha": remote_full[:7],
        "local_sha_full": local_full,
        "remote_sha_full": remote_full,
        "branch": branch,
        "remote_url": url,
    }
