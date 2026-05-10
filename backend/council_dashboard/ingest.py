"""Pure-Python parsers over an ml-trainer ``runs_root``.

We deliberately avoid importing ml-trainer's pydantic models so the
dashboard runs without the ml-trainer Python environment. Every reader
returns plain dicts; the API layer wraps them in pydantic models.
"""

from __future__ import annotations

import json
import os
from datetime import datetime
from pathlib import Path
from typing import Any, Iterable

from council_dashboard.topology import NODES

# Map LLM-call agent names to topology node ids. The recorder uses
# ``empirical_analyst`` / ``theoretical_analyst`` / ``decider`` /
# ``critic`` (sometimes ``master_critic``); normalize all of those.
_AGENT_ALIASES: dict[str, str] = {
    "empirical_analyst": "empirical_analyst",
    "empirical": "empirical_analyst",
    "theoretical_analyst": "theoretical_analyst",
    "theoretical": "theoretical_analyst",
    "decider": "decider",
    "critic": "master_critic",
    "master_critic": "master_critic",
    "feature_developer": "feature_developer",
}


def _agent_id(raw: str) -> str:
    return _AGENT_ALIASES.get(raw, raw)


def _read_jsonl(path: Path) -> list[dict[str, Any]]:
    if not path.exists():
        return []
    out: list[dict[str, Any]] = []
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            out.append(json.loads(line))
        except json.JSONDecodeError:
            # A partially-written line at the tail of a live file is
            # expected; skip and try again on next refresh.
            continue
    return out


def _read_json(path: Path) -> dict[str, Any] | None:
    if not path.exists():
        return None
    try:
        return json.loads(path.read_text())
    except json.JSONDecodeError:
        return None


# ── Sessions ─────────────────────────────────────────────────────────


def list_sessions(runs_root: Path) -> list[dict[str, Any]]:
    """Each subdirectory under ``runs_root`` that contains ``round_*`` dirs."""
    if not runs_root.exists():
        return []
    out: list[dict[str, Any]] = []
    for entry in sorted(runs_root.iterdir()):
        if not entry.is_dir() or entry.name.startswith("."):
            continue
        rounds = sorted(
            d.name for d in entry.iterdir() if d.is_dir() and d.name.startswith("round_")
        )
        if not rounds:
            continue
        runner_state = _read_json(entry / ".runner.json")
        out.append(
            {
                "id": entry.name,
                "path": str(entry),
                "round_count": len(rounds),
                "first_round": rounds[0],
                "last_round": rounds[-1],
                "modified_at": datetime.fromtimestamp(entry.stat().st_mtime).isoformat(),
                "runner": runner_state,
                "stop_pending": (entry / ".STOP").exists(),
            }
        )
    out.sort(key=lambda s: s["modified_at"], reverse=True)
    return out


def session_summary(runs_root: Path, session_id: str) -> dict[str, Any] | None:
    session_dir = runs_root / session_id
    if not session_dir.is_dir():
        return None
    rounds = list_rounds(session_dir)
    promoted = sum(1 for r in rounds for c in r["candidates"] if c["promoted"])
    total_calls = sum(r["llm_call_count"] for r in rounds)
    total_prompt_chars = sum(r["prompt_chars"] for r in rounds)
    total_response_chars = sum(r["response_chars"] for r in rounds)
    return {
        "id": session_id,
        "path": str(session_dir),
        "rounds": rounds,
        "promoted_total": promoted,
        "llm_call_total": total_calls,
        "prompt_chars_total": total_prompt_chars,
        "response_chars_total": total_response_chars,
        "approx_tokens_total": _approx_tokens(total_prompt_chars + total_response_chars),
        "runner": _read_json(session_dir / ".runner.json"),
        "stop_pending": (session_dir / ".STOP").exists(),
    }


# ── Rounds ───────────────────────────────────────────────────────────


def list_rounds(session_dir: Path) -> list[dict[str, Any]]:
    """Lightweight per-round summary (no prompt bodies)."""
    rounds: list[dict[str, Any]] = []
    for round_dir in sorted(d for d in session_dir.iterdir() if d.is_dir()):
        if not round_dir.name.startswith("round_"):
            continue
        rounds.append(round_summary(round_dir))
    return rounds


def round_summary(round_dir: Path) -> dict[str, Any]:
    decision = _read_json(round_dir / "decision.json") or {}
    runs = _read_jsonl(round_dir / "runs.jsonl")
    llm_calls = _read_jsonl(round_dir / "llm_calls.jsonl")

    candidates = [_candidate_summary(c) for c in decision.get("candidates", [])]

    prompt_chars = 0
    response_chars = 0
    per_agent: dict[str, dict[str, Any]] = {}
    session_dir = round_dir.parent  # ml-trainer stores LLM paths relative to session_dir.
    for call in llm_calls:
        prompt_path = session_dir / call.get("prompt_path", "")
        response_path = session_dir / call.get("response_path", "")
        p_size = prompt_path.stat().st_size if prompt_path.exists() else 0
        r_size = response_path.stat().st_size if response_path.exists() else 0
        prompt_chars += p_size
        response_chars += r_size
        agent = _agent_id(call.get("agent", "unknown"))
        slot = per_agent.setdefault(
            agent,
            {
                "agent": agent,
                "calls": 0,
                "prompt_chars": 0,
                "response_chars": 0,
                "wall_seconds": 0.0,
                "approx_tokens": 0,
            },
        )
        slot["calls"] += 1
        slot["prompt_chars"] += p_size
        slot["response_chars"] += r_size
        slot["wall_seconds"] += _wall_seconds(call)
        slot["approx_tokens"] = _approx_tokens(slot["prompt_chars"] + slot["response_chars"])

    return {
        "round_id": decision.get("round_id", round_dir.name),
        "timestamp": decision.get("timestamp"),
        "stop_signal": decision.get("stop_signal"),
        "parent_round_id": decision.get("parent_round_id"),
        "selection_rationale": decision.get("selection_rationale", "")[:500],
        "candidates": candidates,
        "promoted_count": sum(1 for c in candidates if c["promoted"]),
        "candidate_count": len(candidates),
        "executed_count": len(runs),
        "llm_call_count": len(llm_calls),
        "prompt_chars": prompt_chars,
        "response_chars": response_chars,
        "approx_tokens": _approx_tokens(prompt_chars + response_chars),
        "per_agent": list(per_agent.values()),
        "results": _result_summary(runs),
    }


def round_detail(session_dir: Path, round_id: str) -> dict[str, Any] | None:
    round_dir = session_dir / round_id
    if not round_dir.is_dir():
        return None
    decision = _read_json(round_dir / "decision.json")
    runs = _read_jsonl(round_dir / "runs.jsonl")
    llm_calls = _read_jsonl(round_dir / "llm_calls.jsonl")
    enriched_calls = [_enrich_llm_call(round_dir.parent, call) for call in llm_calls]
    return {
        "summary": round_summary(round_dir),
        "decision": decision,
        "runs": runs,
        "llm_calls": enriched_calls,
    }


def _candidate_summary(c: dict[str, Any]) -> dict[str, Any]:
    spec = c.get("spec") or {}
    feats = [f.get("id") for f in spec.get("feature_set", [])]
    return {
        "experiment_id": spec.get("experiment_id"),
        "proposer": c.get("proposer"),
        "promoted": bool(c.get("promoted")),
        "risk_flags": c.get("risk_flags", []),
        "lineage": c.get("lineage"),
        "feature_ids": feats,
        "model_family": (spec.get("model") or {}).get("family"),
        "hidden": (spec.get("model") or {}).get("hidden"),
        "rationale_excerpt": (c.get("rationale") or "")[:240],
    }


def _result_summary(runs: list[dict[str, Any]]) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    for r in runs:
        m = r.get("metrics") or {}
        out.append(
            {
                "experiment_id": r.get("experiment_id"),
                "fingerprint": (r.get("artifacts") or {}).get("fingerprint"),
                "succeeded": r.get("error") is None,
                "test_pearson_r_mean": m.get("test_pearson_r_mean"),
                "val_pearson_r_mean": m.get("val_pearson_r_mean"),
                "bdb2020_pearson_r_mean": m.get("bdb2020_pearson_r_mean"),
                "egfr_pearson_r_mean": m.get("egfr_pearson_r_mean"),
                "mpro_pearson_r_mean": m.get("mpro_pearson_r_mean"),
                "n_seeds_total": m.get("n_seeds_total"),
                "n_seeds_succeeded": m.get("n_seeds_succeeded"),
                "started_at": r.get("started_at"),
                "completed_at": r.get("completed_at"),
            }
        )
    return out


def _wall_seconds(call: dict[str, Any]) -> float:
    started = call.get("started_at")
    completed = call.get("completed_at")
    if not started or not completed:
        return 0.0
    try:
        s = datetime.fromisoformat(started)
        c = datetime.fromisoformat(completed)
        return max((c - s).total_seconds(), 0.0)
    except Exception:
        return 0.0


def _approx_tokens(char_count: int) -> int:
    """Rough chars → tokens approximation (Claude tokenizers run ~3.5–4 chars/tok)."""
    return char_count // 4


def _enrich_llm_call(runs_root: Path, call: dict[str, Any]) -> dict[str, Any]:
    """Attach prompt/response sizes + computed token approximations."""
    prompt_rel = call.get("prompt_path", "")
    response_rel = call.get("response_path", "")
    prompt_path = runs_root / prompt_rel
    response_path = runs_root / response_rel
    p_size = prompt_path.stat().st_size if prompt_path.exists() else 0
    r_size = response_path.stat().st_size if response_path.exists() else 0
    # Optional sidecar with exact token usage; see docs/upstream_patch.md.
    usage_path = response_path.with_suffix(".usage.json") if response_path.exists() else None
    usage = _read_json(usage_path) if usage_path else None
    return {
        **call,
        "agent_id": _agent_id(call.get("agent", "unknown")),
        "prompt_chars": p_size,
        "response_chars": r_size,
        "approx_prompt_tokens": _approx_tokens(p_size),
        "approx_response_tokens": _approx_tokens(r_size),
        "wall_seconds": _wall_seconds(call),
        "exact_usage": usage,
    }


def read_prompt(runs_root: Path, relative: str) -> str | None:
    p = runs_root / relative
    if not p.exists():
        return None
    return p.read_text(errors="replace")


def read_response(runs_root: Path, relative: str) -> Any:
    p = runs_root / relative
    if not p.exists():
        return None
    try:
        return json.loads(p.read_text())
    except json.JSONDecodeError:
        return p.read_text(errors="replace")


# ── Per-agent connectivity overlay ───────────────────────────────────


def topology_overlay(round_or_session: dict[str, Any]) -> dict[str, dict[str, Any]]:
    """Map node_id → {calls, approx_tokens, wall_seconds} for the frontend."""
    per_agent_iter: Iterable[dict[str, Any]]
    if "per_agent" in round_or_session:  # round summary
        per_agent_iter = round_or_session["per_agent"]
    else:  # session summary — sum over rounds
        sums: dict[str, dict[str, Any]] = {}
        for r in round_or_session.get("rounds", []):
            for slot in r.get("per_agent", []):
                a = slot["agent"]
                acc = sums.setdefault(
                    a,
                    {
                        "agent": a,
                        "calls": 0,
                        "approx_tokens": 0,
                        "wall_seconds": 0.0,
                    },
                )
                acc["calls"] += slot["calls"]
                acc["approx_tokens"] += slot["approx_tokens"]
                acc["wall_seconds"] += slot["wall_seconds"]
        per_agent_iter = sums.values()
    out: dict[str, dict[str, Any]] = {}
    valid_ids = {n["id"] for n in NODES}
    for slot in per_agent_iter:
        if slot["agent"] in valid_ids:
            out[slot["agent"]] = slot
    return out
