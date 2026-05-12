"""Council discovery, manifest read/write, and prompt previewing.

A "council" is a directory containing a ``manifest.yaml`` plus the
``prompts/`` and ``resources/`` folders the manifest references. The
canonical example today is ``ml-trainer/ml_trainer/council/``.

This module is intentionally thin:
- discovery + manifest read/write happen here in plain Python (YAML I/O).
- preview rendering shells out to ``scripts/render_preview.py``, which
  imports the ml-trainer ``agent_runtime`` to build the *exact* prompt
  the agent would see at call time. The dashboard does not duplicate
  ml-trainer's rendering logic.
"""

from __future__ import annotations

import json
import shutil
import subprocess
from pathlib import Path
from typing import Any

import yaml


def _scripts_dir() -> Path:
    # backend/council_dashboard/councils.py → ../../scripts/
    return Path(__file__).resolve().parents[2] / "scripts"


def _is_council_dir(d: Path) -> bool:
    return d.is_dir() and (d / "manifest.yaml").exists()


def list_councils(councils_root: Path) -> list[dict[str, Any]]:
    """Return summaries of all councils under ``councils_root``.

    The root may itself be a council (single-council layout) or a parent
    directory containing multiple councils as subdirs.
    """
    out: list[dict[str, Any]] = []
    if _is_council_dir(councils_root):
        out.append(_summary(councils_root))
        return out
    if not councils_root.exists():
        return out
    for child in sorted(councils_root.iterdir()):
        if _is_council_dir(child):
            out.append(_summary(child))
    return out


def _summary(council_dir: Path) -> dict[str, Any]:
    manifest = _read_yaml(council_dir / "manifest.yaml")
    return {
        "name": manifest.get("name", council_dir.name),
        "description": manifest.get("description", ""),
        "path": str(council_dir),
        "agent_ids": [a.get("id") for a in manifest.get("agents", [])],
    }


def _resolve_council_dir(councils_root: Path, name: str) -> Path:
    """Map a council name to its directory."""
    candidates = list_councils(councils_root)
    for c in candidates:
        if c["name"] == name:
            return Path(c["path"])
    raise FileNotFoundError(f"council not found: {name!r}")


def read_manifest(councils_root: Path, name: str) -> dict[str, Any]:
    council_dir = _resolve_council_dir(councils_root, name)
    return _read_yaml(council_dir / "manifest.yaml")


def write_manifest(
    councils_root: Path, name: str, body: dict[str, Any]
) -> Path:
    council_dir = _resolve_council_dir(councils_root, name)
    target = council_dir / "manifest.yaml"
    if "name" not in body or body["name"] != name:
        raise ValueError(
            f"manifest body's name ({body.get('name')!r}) doesn't match URL ({name!r})"
        )
    with target.open("w") as fh:
        yaml.safe_dump(body, fh, sort_keys=False, allow_unicode=True)
    return target


def topology(councils_root: Path, name: str) -> dict[str, Any]:
    """Return the topology block (nodes + edges) declared in the council's manifest."""
    manifest = read_manifest(councils_root, name)
    topo = manifest.get("topology") or {}
    return {
        "nodes": topo.get("nodes", []),
        "edges": topo.get("edges", []),
    }


def list_resources(councils_root: Path, name: str) -> list[dict[str, Any]]:
    """File listing of the council's ``resources/`` dir."""
    council_dir = _resolve_council_dir(councils_root, name)
    manifest = _read_yaml(council_dir / "manifest.yaml")
    rdir = (council_dir / manifest.get("resources_dir", "resources")).resolve()
    if not rdir.exists():
        return []
    out: list[dict[str, Any]] = []
    for f in sorted(rdir.iterdir()):
        if f.is_file():
            out.append({
                "name": f.name,
                "size": f.stat().st_size,
                "mtime": f.stat().st_mtime,
            })
    return out


def read_resource(
    councils_root: Path, name: str, resource_name: str
) -> dict[str, Any]:
    council_dir = _resolve_council_dir(councils_root, name)
    manifest = _read_yaml(council_dir / "manifest.yaml")
    rdir = (council_dir / manifest.get("resources_dir", "resources")).resolve()
    target = rdir / resource_name
    if "/" in resource_name or ".." in resource_name or not target.exists():
        raise FileNotFoundError(f"resource not found: {resource_name!r}")
    return {
        "name": target.name,
        "body": target.read_text(),
        "size": target.stat().st_size,
        "mtime": target.stat().st_mtime,
    }


def write_resource(
    councils_root: Path, name: str, resource_name: str, body: str
) -> dict[str, Any]:
    council_dir = _resolve_council_dir(councils_root, name)
    manifest = _read_yaml(council_dir / "manifest.yaml")
    rdir = (council_dir / manifest.get("resources_dir", "resources")).resolve()
    if "/" in resource_name or ".." in resource_name:
        raise ValueError(f"invalid resource name: {resource_name!r}")
    target = rdir / resource_name
    target.write_text(body)
    return read_resource(councils_root, name, resource_name)


def render_preview(
    councils_root: Path,
    name: str,
    agent_id: str,
    *,
    extra_context: str | None = None,
    ml_trainer_repo: Path,
    manifest_body: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """Shell out to ``scripts/render_preview.py`` to render the prompt.

    When ``manifest_body`` is given, the script reads that body from stdin
    instead of the on-disk file — used for previewing unsaved edits.

    Returns ``{system_prompt, user_prompt, agent: {...}, schema_name}``.
    """
    council_dir = _resolve_council_dir(councils_root, name)
    args = _render_args(council_dir, agent_id, ml_trainer_repo, extra_context,
                        from_body=manifest_body is not None)
    stdin_data = yaml.safe_dump(manifest_body, sort_keys=False) if manifest_body else None
    proc = subprocess.run(
        args, input=stdin_data, capture_output=True, text=True, check=False,
    )
    if proc.returncode != 0:
        raise RuntimeError(
            f"render_preview.py failed (exit {proc.returncode}): "
            f"{proc.stderr[:500]}"
        )
    try:
        return json.loads(proc.stdout)
    except json.JSONDecodeError as e:
        raise RuntimeError(
            f"render_preview.py emitted non-JSON: {proc.stdout[:200]!r}"
        ) from e


def _render_args(
    council_dir: Path,
    agent_id: str,
    ml_trainer_repo: Path,
    extra_context: str | None,
    *,
    from_body: bool,
) -> list[str]:
    uv = shutil.which("uv")
    if uv is None:
        raise RuntimeError(
            "`uv` not found in PATH; required to invoke ml-trainer's "
            "Python env for prompt rendering"
        )
    script = _scripts_dir() / "render_preview.py"
    args = [
        uv, "run", "--directory", str(ml_trainer_repo),
        "python", str(script),
        "--agent-id", agent_id,
        "--ml-trainer-repo", str(ml_trainer_repo),
    ]
    if from_body:
        args.extend(["--council-dir", str(council_dir)])
    else:
        args.extend(["--manifest", str(council_dir / "manifest.yaml")])
    if extra_context:
        args.extend(["--extra-context", extra_context])
    return args


# ── helpers ──────────────────────────────────────────────────────────


def _read_yaml(path: Path) -> dict[str, Any]:
    with path.open() as fh:
        body = yaml.safe_load(fh) or {}
    if not isinstance(body, dict):
        raise ValueError(f"manifest at {path} is not a YAML mapping")
    return body
