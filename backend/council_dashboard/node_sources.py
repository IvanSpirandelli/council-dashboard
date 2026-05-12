"""Per-node source views.

LLM nodes have prompt artifacts (handled by ``council_llm_artifact``).
Code nodes ("kind: code" in the manifest topology — currently the
``validator`` and ``executor``) don't have an LLM artifact; the
"call" *is* the Python that runs. This module gives the dashboard a
way to surface that source for each code node so the user can
inspect what the node actually does without leaving the UI.

Mapping is a static dict — node_id → list[(label, path)] under the
ml-trainer repo. If a path is missing, we skip it; the endpoint still
returns whatever else is available.
"""

from __future__ import annotations

from pathlib import Path

_NODE_SOURCES: dict[str, list[tuple[str, str]]] = {
    "validator": [
        ("ml_trainer/council/dedup.py", "ml_trainer/council/dedup.py"),
        (
            "ml_trainer/council/loop.py · _attach_dedup_flags",
            "ml_trainer/council/loop.py",
        ),
    ],
    "executor": [
        ("ml_trainer/executors/local.py", "ml_trainer/executors/local.py"),
        ("ml_trainer/executors/multi_seed.py", "ml_trainer/executors/multi_seed.py"),
    ],
}


def list_sources(node_id: str) -> list[str]:
    """Labels for the source views available for this node, in order."""
    return [label for label, _ in _NODE_SOURCES.get(node_id, [])]


def read_sources(repo_root: Path, node_id: str) -> list[dict[str, str]]:
    """Return ``[{label, path, body}]`` for every source mapped to ``node_id``.

    Skips entries whose path is missing under ``repo_root`` instead of
    erroring — partial coverage is still useful.
    """
    out: list[dict[str, str]] = []
    for label, rel in _NODE_SOURCES.get(node_id, []):
        p = (repo_root / rel).resolve()
        if not p.exists() or not p.is_file():
            continue
        try:
            body = p.read_text(errors="replace")
        except OSError:
            continue
        out.append({"label": label, "path": str(p), "body": body})
    return out


def has_source(node_id: str) -> bool:
    return node_id in _NODE_SOURCES


__all__ = ["has_source", "list_sources", "read_sources"]
