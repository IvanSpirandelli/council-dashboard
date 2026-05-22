"""FastAPI app exposing the dashboard's read + control surface."""

from __future__ import annotations

import shutil
from pathlib import Path
from typing import Any

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

from council_dashboard import councils as councils_mod
from council_dashboard import ingest, kinds, node_sources, supervisor
from council_dashboard.config import Settings
from council_dashboard.scaffold import routes as scaffold_routes


def _canonical_session_dir(name: str) -> Path:
    """Each council has one persistent session dir at ``runs_root/<name>/``."""
    return settings.runs_root / name


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

# Register every shipped kind (panels + providers) once at import.
kinds.bootstrap(models_root=settings.models_root)
app.include_router(scaffold_routes.build_router(councils_root=settings.councils_root))


# ── Models ───────────────────────────────────────────────────────────


class HealthResponse(BaseModel):
    ok: bool
    runs_root: str
    runs_root_exists: bool
    models_root: str
    ml_trainer_repo: str
    councils_root: str
    councils_root_exists: bool
    dashboard_repo: str


class ManifestPayload(BaseModel):
    body: dict[str, Any]


class ResourceWritePayload(BaseModel):
    body: str


class PreviewRequest(BaseModel):
    extra_context: str | None = None


class PreviewFromBodyRequest(BaseModel):
    body: dict[str, Any]
    extra_context: str | None = None


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
        councils_root=str(settings.councils_root),
        councils_root_exists=settings.councils_root.exists(),
        dashboard_repo=str(Path(__file__).resolve().parents[2]),
    )


@app.get("/topology")
def topology(council: str) -> dict[str, Any]:
    """Topology of the named council."""
    try:
        return councils_mod.topology(settings.councils_root, council)
    except FileNotFoundError as e:
        raise HTTPException(404, str(e))


def _topology_nodes(council: str) -> list[dict[str, Any]]:
    """Return the topology's node list (with id + kind) for overlay computation."""
    try:
        topo = councils_mod.topology(settings.councils_root, council)
    except FileNotFoundError:
        return []
    return [n for n in topo.get("nodes", []) if n.get("id")]


# ── Council builder ──────────────────────────────────────────────────


@app.get("/councils")
def councils_list() -> list[dict[str, Any]]:
    return councils_mod.list_councils(settings.councils_root)


@app.get("/councils/{name}")
def council_get(name: str) -> dict[str, Any]:
    try:
        manifest = councils_mod.read_manifest(settings.councils_root, name)
    except FileNotFoundError as e:
        raise HTTPException(404, str(e))
    return {
        "manifest": manifest,
        "resources": councils_mod.list_resources(settings.councils_root, name),
    }


@app.put("/councils/{name}")
def council_put(name: str, payload: ManifestPayload) -> dict[str, Any]:
    try:
        path = councils_mod.write_manifest(
            settings.councils_root, name, payload.body
        )
    except (FileNotFoundError, ValueError) as e:
        raise HTTPException(400, str(e))
    return {"ok": True, "path": str(path)}


@app.get("/councils/{name}/resources/{resource_name}")
def council_resource_get(name: str, resource_name: str) -> dict[str, Any]:
    try:
        return councils_mod.read_resource(
            settings.councils_root, name, resource_name
        )
    except FileNotFoundError as e:
        raise HTTPException(404, str(e))


@app.put("/councils/{name}/resources/{resource_name}")
def council_resource_put(
    name: str, resource_name: str, payload: ResourceWritePayload
) -> dict[str, Any]:
    try:
        return councils_mod.write_resource(
            settings.councils_root, name, resource_name, payload.body
        )
    except (FileNotFoundError, ValueError) as e:
        raise HTTPException(400, str(e))


@app.post("/councils/{name}/agents/{agent_id}/preview")
def council_preview(
    name: str, agent_id: str, payload: PreviewRequest | None = None
) -> dict[str, Any]:
    extra = payload.extra_context if payload else None
    try:
        return councils_mod.render_preview(
            settings.councils_root,
            name,
            agent_id,
            extra_context=extra,
            ml_trainer_repo=settings.ml_trainer_repo,
        )
    except FileNotFoundError as e:
        raise HTTPException(404, str(e))
    except RuntimeError as e:
        raise HTTPException(500, str(e))


# ── Council-centric session + performance ───────────────────────────


@app.get("/councils/{name}/session")
def council_session(name: str) -> dict[str, Any]:
    """Summary of the canonical session dir for this council.

    The canonical layout is ``runs_root/<name>/``: one persistent
    directory the council appends rounds to.
    """
    try:
        councils_mod.read_manifest(settings.councils_root, name)
    except FileNotFoundError as e:
        raise HTTPException(404, str(e))

    session_dir = _canonical_session_dir(name)
    summary = ingest.session_summary(settings.runs_root, name)
    if summary is None:
        runner = supervisor.read_runner_state(session_dir)
        return {
            "id": name,
            "council": name,
            "path": str(session_dir),
            "rounds": [],
            "promoted_total": 0,
            "llm_call_total": 0,
            "approx_tokens_total": 0,
            "runner": runner,
            "stop_pending": (session_dir / ".STOP").exists(),
            "topology_overlay": {},
            "current_round_id": (runner or {}).get("current_round"),
            "active_call": None,
        }
    summary["council"] = name
    summary["topology_overlay"] = ingest.topology_overlay(
        summary, _topology_nodes(name)
    )
    return summary


@app.get("/councils/{name}/rounds/{round_id}")
def council_round(name: str, round_id: str) -> dict[str, Any]:
    session_dir = _canonical_session_dir(name)
    detail = ingest.round_detail(session_dir, round_id)
    if detail is None:
        raise HTTPException(404, f"unknown round: {name}/{round_id}")
    detail["topology_overlay"] = ingest.topology_overlay(
        detail["summary"], _topology_nodes(name)
    )
    return detail


@app.get("/councils/{name}/nodes/{node_id}/rendered")
def council_node_rendered(name: str, node_id: str) -> dict[str, Any]:
    """Rendered body of a generated input node.

    Backed by ``scripts/render_resource.py`` → ``ResourceBundle``. The
    dashboard hits this when an input tile with ``kind: generated`` is
    tapped so the user sees the live ``.md`` the agents actually consume.
    """
    try:
        return councils_mod.render_resource(
            settings.councils_root,
            name,
            node_id,
            ml_trainer_repo=settings.ml_trainer_repo,
        )
    except FileNotFoundError as e:
        raise HTTPException(404, str(e))
    except KeyError as e:
        raise HTTPException(404, str(e))
    except RuntimeError as e:
        raise HTTPException(500, str(e))


@app.get("/councils/{name}/nodes/{node_id}/source")
def council_node_source(name: str, node_id: str) -> dict[str, Any]:
    """Source views for a code node (validator/executor).

    Returns ``{"node_id", "sources": [{label, path, body}]}``. Empty
    ``sources`` for LLM nodes or unknown ids — the frontend treats that
    as "this node has no Python to show".
    """
    del name  # source is per-node, not per-council, today.
    if not node_sources.has_source(node_id):
        return {"node_id": node_id, "sources": []}
    return {
        "node_id": node_id,
        "sources": node_sources.read_sources(settings.ml_trainer_repo, node_id),
    }


@app.get("/councils/{name}/rounds/{round_id}/one-round-command")
def council_round_one_round_command(name: str, round_id: str) -> dict[str, Any]:
    """Snapshot of the one-round command that was pinned to this round.

    Returns ``{"body": "<text>"}`` if a snapshot exists, ``{"body": ""}``
    if the round committed without an active command.
    """
    if "/" in round_id or ".." in round_id:
        raise HTTPException(400, "invalid round_id")
    snapshot = (
        _canonical_session_dir(name) / round_id / "one_round_command.md"
    )
    if not snapshot.exists():
        return {"body": ""}
    return {"body": snapshot.read_text()}


@app.get("/councils/{name}/rounds/{round_id}/llm/{filename}")
def council_llm_artifact(
    name: str, round_id: str, filename: str
) -> dict[str, Any]:
    if "/" in filename or ".." in filename:
        raise HTTPException(400, "invalid filename")
    base = _canonical_session_dir(name) / round_id / "llm" / filename
    if not base.exists():
        raise HTTPException(404, f"missing artifact: {filename}")
    text = base.read_text(errors="replace")
    return {"filename": filename, "size": base.stat().st_size, "body": text}


@app.get("/councils/{name}/launch-config")
def council_get_launch_config(name: str) -> dict[str, Any]:
    session_dir = _canonical_session_dir(name)
    config = supervisor.read_launch_config(session_dir)
    return {
        "exists": config is not None,
        "config": config,
        "path": str(supervisor.launch_path(session_dir)),
    }


@app.post("/councils/{name}/launch-config")
def council_set_launch_config(name: str, req: StartRequest) -> dict[str, Any]:
    session_dir = _canonical_session_dir(name)
    supervisor.write_launch_config(session_dir, req.model_dump())
    return {"ok": True, "path": str(supervisor.launch_path(session_dir))}


@app.post("/councils/{name}/start", response_model=StartResponse)
def council_start(name: str) -> StartResponse:
    session_dir = _canonical_session_dir(name)
    try:
        state = supervisor.start(session_dir)
    except FileNotFoundError as e:
        raise HTTPException(400, str(e))
    return StartResponse(state=state)


@app.post("/councils/{name}/stop")
def council_stop(name: str, force: bool = False) -> dict[str, Any]:
    session_dir = _canonical_session_dir(name)
    if force:
        return supervisor.force_stop(session_dir)
    return supervisor.request_stop(session_dir)


@app.post("/councils/{name}/clear-stop")
def council_clear_stop(name: str) -> dict[str, Any]:
    session_dir = _canonical_session_dir(name)
    supervisor.clear_stop(session_dir)
    return {"ok": True}


@app.post("/councils/{name}/incomplete-rounds/delete")
def council_delete_incomplete_rounds(name: str) -> dict[str, Any]:
    """Trash round dirs that lack ``decision.json``.

    Refuses while the runner is alive — the launcher's ``_next_round_id``
    skips any existing dir, so a dangling round_NNN would otherwise be
    silently abandoned on restart.
    """
    session_dir = _canonical_session_dir(name)
    runner = supervisor.read_runner_state(session_dir)
    if runner and runner.get("alive"):
        raise HTTPException(409, "council is running; stop it first")
    deleted: list[str] = []
    if session_dir.exists():
        for round_dir in sorted(d for d in session_dir.iterdir() if d.is_dir()):
            if not round_dir.name.startswith("round_"):
                continue
            if (round_dir / "decision.json").exists():
                continue
            shutil.rmtree(round_dir)
            deleted.append(round_dir.name)
    return {"deleted": deleted}


@app.post("/councils/{name}/agents/{agent_id}/preview-from-body")
def council_preview_from_body(
    name: str, agent_id: str, payload: PreviewFromBodyRequest,
) -> dict[str, Any]:
    """Render against an in-flight (unsaved) manifest body."""
    try:
        return councils_mod.render_preview(
            settings.councils_root,
            name,
            agent_id,
            extra_context=payload.extra_context,
            ml_trainer_repo=settings.ml_trainer_repo,
            manifest_body=payload.body,
        )
    except FileNotFoundError as e:
        raise HTTPException(404, str(e))
    except RuntimeError as e:
        raise HTTPException(500, str(e))
