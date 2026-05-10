"""FastAPI app exposing the dashboard's read + control surface."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path
from typing import Any

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

from council_dashboard import ingest, supervisor
from council_dashboard.config import Settings
from council_dashboard.topology import topology_dict

settings = Settings.load()
app = FastAPI(title="council-dashboard", version="0.1.0")

# Flutter web dev (`flutter run -d chrome`) and a subsequent flutter
# build serve from arbitrary localhost ports; allow them all.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


# ── Models ───────────────────────────────────────────────────────────


class HealthResponse(BaseModel):
    ok: bool
    runs_root: str
    runs_root_exists: bool
    models_root: str
    ml_trainer_repo: str


class StartRequest(BaseModel):
    cmd: list[str]
    cwd: str | None = None
    env: dict[str, str] = {}


class StartResponse(BaseModel):
    state: dict[str, Any]


# ── Health / config ──────────────────────────────────────────────────


@app.get("/health", response_model=HealthResponse)
def health() -> HealthResponse:
    return HealthResponse(
        ok=True,
        runs_root=str(settings.runs_root),
        runs_root_exists=settings.runs_root.exists(),
        models_root=str(settings.models_root),
        ml_trainer_repo=str(settings.ml_trainer_repo),
    )


@app.get("/topology")
def topology() -> dict[str, Any]:
    return topology_dict()


# ── Sessions ─────────────────────────────────────────────────────────


@app.get("/sessions")
def sessions() -> list[dict[str, Any]]:
    return ingest.list_sessions(settings.runs_root)


@app.get("/sessions/{session_id}")
def session(session_id: str) -> dict[str, Any]:
    summary = ingest.session_summary(settings.runs_root, session_id)
    if summary is None:
        raise HTTPException(404, f"unknown session: {session_id}")
    summary["topology_overlay"] = ingest.topology_overlay(summary)
    return summary


@app.get("/sessions/{session_id}/rounds/{round_id}")
def round_endpoint(session_id: str, round_id: str) -> dict[str, Any]:
    session_dir = settings.runs_root / session_id
    detail = ingest.round_detail(session_dir, round_id)
    if detail is None:
        raise HTTPException(404, f"unknown round: {session_id}/{round_id}")
    detail["topology_overlay"] = ingest.topology_overlay(detail["summary"])
    return detail


@app.get("/sessions/{session_id}/rounds/{round_id}/llm/{filename}")
def llm_artifact(session_id: str, round_id: str, filename: str) -> dict[str, Any]:
    """Return the body of one prompt or response file.

    Filename should be the basename, e.g. ``empirical_analyst_t1.prompt.txt``.
    """
    if "/" in filename or ".." in filename:
        raise HTTPException(400, "invalid filename")
    base = settings.runs_root / session_id / round_id / "llm" / filename
    if not base.exists():
        raise HTTPException(404, f"missing artifact: {filename}")
    text = base.read_text(errors="replace")
    return {"filename": filename, "size": base.stat().st_size, "body": text}


# ── Process control ──────────────────────────────────────────────────


@app.post("/sessions/{session_id}/launch-config")
def set_launch_config(session_id: str, req: StartRequest) -> dict[str, Any]:
    session_dir = settings.runs_root / session_id
    supervisor.write_launch_config(session_dir, req.model_dump())
    return {"ok": True, "path": str(supervisor._launch_path(session_dir))}


@app.post("/sessions/{session_id}/start", response_model=StartResponse)
def start_session(session_id: str) -> StartResponse:
    session_dir = settings.runs_root / session_id
    try:
        state = supervisor.start(session_dir)
    except FileNotFoundError as e:
        raise HTTPException(400, str(e))
    return StartResponse(state=state)


@app.post("/sessions/{session_id}/stop")
def stop_session(session_id: str, force: bool = False) -> dict[str, Any]:
    session_dir = settings.runs_root / session_id
    if force:
        return supervisor.force_stop(session_dir)
    return supervisor.request_stop(session_dir)


@app.post("/sessions/{session_id}/clear-stop")
def clear_stop(session_id: str) -> dict[str, Any]:
    session_dir = settings.runs_root / session_id
    supervisor.clear_stop(session_dir)
    return {"ok": True}


# ── Performance table ────────────────────────────────────────────────


@app.get("/performance-table")
def performance_table(
    session: str | None = None,
    round_id: str | None = None,
    sort: str = "cl2",
    asc: bool = False,
    all_variants: bool = False,
) -> dict[str, Any]:
    """Wrap ``scripts/performance_table.py``; returns parsed rows + raw text."""
    script = Path(__file__).resolve().parents[2] / "scripts" / "performance_table.py"
    args: list[str] = [sys.executable, str(script), "--json"]
    if session:
        args += ["--session", str(settings.runs_root / session)]
    if round_id:
        args += ["--round", round_id]
    args += ["--sort", sort]
    if asc:
        args.append("--asc")
    if all_variants:
        args.append("--all-variants")
    args += ["--models-root", str(settings.models_root)]
    proc = subprocess.run(args, capture_output=True, text=True, check=False)
    if proc.returncode != 0:
        raise HTTPException(500, f"performance_table.py failed: {proc.stderr[:400]}")
    import json as _json

    try:
        payload = _json.loads(proc.stdout)
    except _json.JSONDecodeError:
        raise HTTPException(500, "performance_table.py emitted non-JSON output")
    return payload
