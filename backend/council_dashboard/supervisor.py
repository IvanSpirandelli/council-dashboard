"""Supervise a long-running council subprocess.

The dashboard does not import the council factory itself — that lives
in user-controlled launch scripts under ``ml-trainer``. Instead we
record one ``launch.json`` per session that says *how* to launch the
runner, and we own the lifecycle:

- start  : fork the configured command, write ``.runner.json``.
- stop   : create ``.STOP`` so the wrapper exits after the next round;
           also send SIGTERM as a backstop.
- resume : same as start, against the same session_dir.

We don't try to embed council code; we shell out to whatever script the
user chose. The wrapper at ``scripts/launch_council.py`` provides a
convenient default that respects ``.STOP``.
"""

from __future__ import annotations

import json
import os
import signal
import subprocess
from datetime import datetime
from pathlib import Path
from typing import Any

STATE_FILE = ".runner.json"
STOP_FILE = ".STOP"
LAUNCH_FILE = ".launch.json"


def _state_path(session_dir: Path) -> Path:
    return session_dir / STATE_FILE


def _stop_path(session_dir: Path) -> Path:
    return session_dir / STOP_FILE


def _launch_path(session_dir: Path) -> Path:
    return session_dir / LAUNCH_FILE


def read_runner_state(session_dir: Path) -> dict[str, Any] | None:
    p = _state_path(session_dir)
    if not p.exists():
        return None
    try:
        state = json.loads(p.read_text())
    except json.JSONDecodeError:
        return None
    pid = state.get("pid")
    state["alive"] = bool(pid) and _is_alive(pid)
    return state


def _is_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except OSError:
        return False
    return True


def write_launch_config(session_dir: Path, config: dict[str, Any]) -> None:
    """Persist the launch command for this session.

    Expected shape:
        {"cmd": [...], "cwd": "/abs/path", "env": {"K": "V"}}
    """
    session_dir.mkdir(parents=True, exist_ok=True)
    _launch_path(session_dir).write_text(json.dumps(config, indent=2))


def read_launch_config(session_dir: Path) -> dict[str, Any] | None:
    p = _launch_path(session_dir)
    if not p.exists():
        return None
    try:
        return json.loads(p.read_text())
    except json.JSONDecodeError:
        return None


def start(session_dir: Path) -> dict[str, Any]:
    """Launch (or resume) the council against ``session_dir``.

    Reads the launch command from ``session_dir/.launch.json``. Clears
    any stale ``.STOP``. Writes ``.runner.json`` with PID + timestamps.
    """
    config = read_launch_config(session_dir)
    if config is None:
        raise FileNotFoundError(
            f"no .launch.json under {session_dir}; write one first"
        )
    existing = read_runner_state(session_dir)
    if existing and existing.get("alive"):
        return existing  # idempotent: already running.
    _stop_path(session_dir).unlink(missing_ok=True)
    cmd = config["cmd"]
    cwd = config.get("cwd")
    env = {**os.environ, **config.get("env", {})}
    log_path = session_dir / "supervisor.log"
    log_fh = open(log_path, "ab", buffering=0)
    proc = subprocess.Popen(
        cmd,
        cwd=cwd,
        env=env,
        stdout=log_fh,
        stderr=subprocess.STDOUT,
        start_new_session=True,
    )
    state = {
        "pid": proc.pid,
        "started_at": datetime.now().isoformat(),
        "cmd": cmd,
        "cwd": cwd,
        "log_path": str(log_path),
        "status": "running",
    }
    _state_path(session_dir).write_text(json.dumps(state, indent=2))
    state["alive"] = True
    return state


def request_stop(session_dir: Path) -> dict[str, Any]:
    """Cooperative stop: write ``.STOP`` so the runner exits cleanly."""
    _stop_path(session_dir).touch()
    state = read_runner_state(session_dir) or {}
    state["stop_pending"] = True
    return state


def force_stop(session_dir: Path) -> dict[str, Any]:
    """SIGTERM the running process. Used as a fallback to ``request_stop``."""
    state = read_runner_state(session_dir)
    if not state or not state.get("alive"):
        return state or {"alive": False}
    pid = state["pid"]
    try:
        os.killpg(os.getpgid(pid), signal.SIGTERM)
    except ProcessLookupError:
        pass
    state["status"] = "stopping"
    _state_path(session_dir).write_text(json.dumps(state, indent=2))
    state["alive"] = _is_alive(pid)
    return state


def clear_stop(session_dir: Path) -> None:
    _stop_path(session_dir).unlink(missing_ok=True)
