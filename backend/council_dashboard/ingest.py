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

# Map LLM-call agent names to topology node ids. Old sessions (pre-2026-05-10)
# recorded the critic as ``"critic"``; the manifest-driven runtime records
# its manifest id ``"master_critic"``. Keep both forms readable.
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


def session_summary(runs_root: Path, session_id: str) -> dict[str, Any] | None:
    session_dir = runs_root / session_id
    if not session_dir.is_dir():
        return None
    rounds = list_rounds(session_dir)
    promoted = sum(1 for r in rounds for c in r["candidates"] if c["promoted"])
    total_calls = sum(r["llm_call_count"] for r in rounds)
    total_prompt_chars = sum(r["prompt_chars"] for r in rounds)
    total_response_chars = sum(r["response_chars"] for r in rounds)
    runner = _read_json(session_dir / ".runner.json")
    if runner and runner.get("pid"):
        runner["alive"] = _pid_alive(int(runner["pid"]))
    current_round_id = (runner or {}).get("current_round")
    active_call = None
    for r in rounds:
        if r["round_id"] == current_round_id and r.get("active_call"):
            active_call = r["active_call"]
            break
    return {
        "id": session_id,
        "path": str(session_dir),
        "rounds": rounds,
        "promoted_total": promoted,
        "llm_call_total": total_calls,
        "prompt_chars_total": total_prompt_chars,
        "response_chars_total": total_response_chars,
        "approx_tokens_total": _approx_tokens(total_prompt_chars + total_response_chars),
        "runner": runner,
        "stop_pending": (session_dir / ".STOP").exists(),
        "current_round_id": current_round_id,
        "active_call": active_call,
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
    decision_path = round_dir / "decision.json"
    decision = _read_json(decision_path) or {}
    has_decision = decision_path.exists()
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

    in_flight = _read_in_flight_sentinels(round_dir) if not has_decision else []
    active_agents = [_agent_id(c["agent"]) for c in in_flight]
    # Code-phase sentinels mirror the LLM in-progress files for validator
    # and executor — the loop writes them while the phase is running.
    active_code_nodes = [
        name
        for name in ("validator", "executor")
        if (round_dir / f"{name}.in_progress").exists()
    ]
    # Backward-compatible single-call summary (latest start wins).
    active_call: dict[str, Any] | None = None
    if in_flight:
        latest = max(in_flight, key=lambda c: c.get("started_at", ""))
        active_call = {
            "agent": _agent_id(latest["agent"]),
            "started_at": latest.get("started_at"),
        }
    promoted_count = sum(1 for c in candidates if c["promoted"])
    # Executor runs after the LLM phase: decision.json is written first,
    # then runs.jsonl is appended one entry per promoted spec.
    executor_active = has_decision and len(runs) < promoted_count
    if has_decision and not executor_active:
        status = "completed"
    else:
        status = "running"
    return {
        "round_id": decision.get("round_id", round_dir.name),
        "timestamp": decision.get("timestamp"),
        "stop_signal": decision.get("stop_signal"),
        "parent_round_id": decision.get("parent_round_id"),
        "selection_rationale": decision.get("selection_rationale", "")[:500],
        "candidates": candidates,
        "promoted_count": promoted_count,
        "candidate_count": len(candidates),
        "executed_count": len(runs),
        "llm_call_count": len(llm_calls),
        "prompt_chars": prompt_chars,
        "response_chars": response_chars,
        "approx_tokens": _approx_tokens(prompt_chars + response_chars),
        "per_agent": list(per_agent.values()),
        "results": _result_summary(runs),
        "status": status,
        "active_call": active_call,
        "active_agents": active_agents,
        "active_code_nodes": active_code_nodes,
        "executor_active": executor_active,
        # decider_done lets the validator say it's "done" once any decider
        # call has been recorded — the decider only runs after validator
        # finishes.
        "decider_done": any(
            slot["agent"] == "decider" for slot in per_agent.values()
        ),
    }


def _pid_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except OSError:
        return False
    return True


def _read_in_flight_sentinels(round_dir: Path) -> list[dict[str, Any]]:
    """Read every ``<round>/llm/*.in_progress.json`` sentinel.

    The ml-trainer recorder writes one of these before each chat call and
    removes it on completion. This is the only live-state signal available
    while a call is in flight — ``llm_calls.jsonl`` is only appended to
    after the response arrives.
    """
    llm_dir = round_dir / "llm"
    if not llm_dir.is_dir():
        return []
    out: list[dict[str, Any]] = []
    for p in sorted(llm_dir.glob("*.in_progress.json")):
        try:
            blob = json.loads(p.read_text())
        except (json.JSONDecodeError, OSError):
            continue
        if isinstance(blob, dict) and blob.get("agent"):
            out.append(blob)
    return out


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
    except (TypeError, ValueError):
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


def topology_overlay(
    round_or_session: dict[str, Any],
    nodes: list[dict[str, Any]],
) -> dict[str, dict[str, Any]]:
    """Map node_id → overlay entry (calls, tokens, wall_seconds, active, state).

    ``nodes`` is the full topology node list (with ``id`` + ``kind``). The
    overlay only attaches data the topology can render and uses ``kind`` to
    derive a unified lifecycle state (``idle | working | running | done``)
    the frontend can render uniformly.

    For a session, the overlay reflects the *current* round (or the
    latest one if the launcher is idle) — not a sum across history.
    """
    kinds_by_id = {n["id"]: n.get("kind", "llm") for n in nodes if n.get("id")}
    valid_ids = set(kinds_by_id)

    chosen: dict[str, Any] | None
    if "per_agent" in round_or_session:  # round summary
        chosen = round_or_session
    else:  # session summary — pick a single round to display
        rounds = round_or_session.get("rounds", []) or []
        current_id = round_or_session.get("current_round_id")
        chosen = None
        if current_id:
            for r in rounds:
                if r.get("round_id") == current_id:
                    chosen = r
                    break
        if chosen is None and rounds:
            chosen = rounds[-1]  # fallback: latest completed round

    per_agent_iter: Iterable[dict[str, Any]] = (
        (chosen or {}).get("per_agent", []) if chosen else []
    )
    active_agents: set[str] = set(
        (chosen or {}).get("active_agents", []) if chosen else []
    )
    active_code_nodes: set[str] = set(
        (chosen or {}).get("active_code_nodes", []) if chosen else []
    )
    executor_active = bool((chosen or {}).get("executor_active")) if chosen else False
    decider_done = bool((chosen or {}).get("decider_done")) if chosen else False
    promoted_count = int((chosen or {}).get("promoted_count", 0)) if chosen else 0
    executed_count = int((chosen or {}).get("executed_count", 0)) if chosen else 0
    round_status = (chosen or {}).get("status") if chosen else None

    overlay: dict[str, dict[str, Any]] = {}
    for slot in per_agent_iter:
        if slot["agent"] not in valid_ids:
            continue
        slot = {**slot, "active": slot["agent"] in active_agents}
        overlay[slot["agent"]] = slot
    # In-flight LLM agents without prior completed calls still need entries.
    for agent_id in active_agents:
        if agent_id not in valid_ids or agent_id in overlay:
            continue
        overlay[agent_id] = {
            "agent": agent_id,
            "calls": 0,
            "approx_tokens": 0,
            "wall_seconds": 0.0,
            "active": True,
        }
    # Code nodes never have LLM calls, so they never appear in per_agent.
    # Synthesize entries for each so the frontend sees the lifecycle state.
    for node_id, kind in kinds_by_id.items():
        if kind != "code":
            continue
        active = node_id in active_code_nodes or (
            node_id == "executor" and executor_active
        )
        entry = overlay.get(
            node_id,
            {
                "agent": node_id,
                "calls": 0,
                "approx_tokens": 0,
                "wall_seconds": 0.0,
            },
        )
        entry["active"] = active
        entry["done"] = _code_done(
            node_id,
            active=active,
            decider_done=decider_done,
            promoted_count=promoted_count,
            executed_count=executed_count,
            round_status=round_status,
        )
        overlay[node_id] = entry
    # Final pass: attach unified state for every entry so the frontend can
    # render llm/code with a single switch.
    for node_id, entry in overlay.items():
        entry["state"] = _node_state(
            kinds_by_id.get(node_id, "llm"),
            active=bool(entry.get("active")),
            calls=int(entry.get("calls", 0) or 0),
            done=bool(entry.get("done")),
        )
    return overlay


def _code_done(
    node_id: str,
    *,
    active: bool,
    decider_done: bool,
    promoted_count: int,
    executed_count: int,
    round_status: str | None,
) -> bool:
    """Has this code phase finished running for the chosen round?"""
    if active:
        return False
    if node_id == "validator":
        # Validator runs before the decider; the moment any decider call
        # is on record (or the round is fully committed) the phase is done.
        return decider_done or round_status == "completed"
    if node_id == "executor":
        if round_status == "completed":
            return True
        return promoted_count > 0 and executed_count >= promoted_count
    return False


def _node_state(
    kind: str, *, active: bool, calls: int, done: bool
) -> str:
    """Lifecycle label the frontend renders verbatim."""
    if kind == "llm":
        if active:
            return "working"
        if calls > 0:
            return "done"
        return "idle"
    # code node
    if active:
        return "running"
    if done:
        return "done"
    return "idle"
