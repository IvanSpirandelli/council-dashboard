#!/usr/bin/env python3
"""Cooperative-stop wrapper around ``ml_trainer.council.run_council``.

The dashboard's supervisor invokes this script in a subprocess. It runs
one council round at a time via ``run_round`` and checks for
``runs_root/.STOP`` between rounds, so a stop request is honoured at
the next clean boundary instead of mid-round.

Configuring which agents to wire up is the user's responsibility — the
council factory is provided through the ``--factory`` flag, which must
point to a Python callable that accepts ``(runs_root, **kwargs)`` and
returns a dict with the keys::

    {
        "analysts": {role: AnalystAgent, ...},  # dict, any number of seats
        "decider": DeciderAgent,
        "critic": MasterCriticAgent,
        "executor": Executor,
        "bundle": ResourceBundle,
    }

The default factory ``ml_trainer.council.factory:build`` enumerates the
analyst seats from the manifest. MLP yields 3 (empirical, theoretical,
oob); GNN yields 2 (anchor, frontier).

Then invoke::

    uv run python scripts/launch_council.py \\
        --runs-root /abs/path/to/runs/council_session_X \\
        --factory my_council_factory:build \\
        --max-rounds 30

The wrapper handles ``.STOP`` and SIGTERM. It writes
``.runner.json`` updates between rounds so the dashboard can poll.
"""

from __future__ import annotations

import argparse
import importlib
import json
import logging
import signal
import sys
from datetime import datetime
from pathlib import Path
from typing import Any

logger = logging.getLogger("launch_council")


def _resolve_factory(spec: str):
    """``module.path:callable_name`` → callable."""
    if ":" not in spec:
        raise ValueError(f"factory must be 'module:callable', got: {spec}")
    module_name, func_name = spec.split(":", 1)
    module = importlib.import_module(module_name)
    fn = getattr(module, func_name, None)
    if fn is None:
        raise AttributeError(f"{module_name} has no attribute {func_name}")
    return fn


def _write_runner_state(runs_root: Path, **kwargs: Any) -> None:
    state_path = runs_root / ".runner.json"
    existing: dict[str, Any] = {}
    if state_path.exists():
        try:
            existing = json.loads(state_path.read_text())
        except json.JSONDecodeError:
            pass
    existing.update(kwargs)
    state_path.write_text(json.dumps(existing, indent=2))


def _stop_requested(runs_root: Path) -> bool:
    return (runs_root / ".STOP").exists()


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--runs-root", required=True, type=Path)
    ap.add_argument("--factory", required=True, help="module.path:callable returning a dict of council seats.")
    ap.add_argument("--factory-kwargs", default="{}", help="JSON dict of kwargs forwarded to the factory.")
    ap.add_argument("--max-rounds", type=int, default=30)
    ap.add_argument("--cost-cap-active", action="store_true")
    ap.add_argument("--max-critic-turns", type=int, default=2)
    args = ap.parse_args()

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(name)s] %(message)s",
    )

    runs_root: Path = args.runs_root.expanduser().resolve()
    runs_root.mkdir(parents=True, exist_ok=True)

    # ml-trainer must be importable. It's installed with `uv sync` inside
    # the ml-trainer repo; the user's factory module typically lives there
    # too, so we let PYTHONPATH handle it.
    from ml_trainer.council.loop import run_round  # noqa: E402
    from ml_trainer.tracking import list_rounds, read_decision  # noqa: E402

    factory = _resolve_factory(args.factory)
    seats = factory(runs_root, **json.loads(args.factory_kwargs))

    # Re-load history from disk → makes "resume" automatic.
    history = []
    for rid in list_rounds(runs_root):
        try:
            history.append(read_decision(runs_root, rid))
        except Exception as e:  # noqa: BLE001
            logger.warning("could not load %s: %s", rid, e)

    _write_runner_state(
        runs_root,
        status="running",
        started_at=datetime.now().isoformat(),
        history_size=len(history),
    )

    def _on_term(*_a: Any) -> None:
        logger.info("SIGTERM received → cooperative stop requested.")
        (runs_root / ".STOP").touch()

    signal.signal(signal.SIGTERM, _on_term)
    signal.signal(signal.SIGINT, _on_term)

    rounds_done = 0
    try:
        for i in range(args.max_rounds):
            if _stop_requested(runs_root):
                logger.info("stop requested before round; exiting cleanly.")
                _write_runner_state(runs_root, status="stopped_by_request")
                break
            round_id = _next_round_id(runs_root)
            logger.info("starting %s", round_id)
            _write_runner_state(runs_root, current_round=round_id, status="running")
            decision = run_round(
                round_id=round_id,
                runs_root=runs_root,
                executor=seats["executor"],
                analysts=seats["analysts"],
                decider=seats["decider"],
                critic=seats["critic"],
                bundle=seats.get("bundle"),
                history=history,
                parent_round_id=history[-1].round_id if history else None,
                rounds_remaining=args.max_rounds - i - 1,
                cost_cap_active=args.cost_cap_active,
                max_critic_turns=args.max_critic_turns,
            )
            history.append(decision)
            rounds_done += 1
            _write_runner_state(
                runs_root,
                last_completed_round=round_id,
                rounds_done=rounds_done,
            )
            if decision.stop_signal:
                logger.info("council emitted stop_signal=%s", decision.stop_signal)
                _write_runner_state(
                    runs_root,
                    status=f"stopped_council_{decision.stop_signal}",
                )
                break
        else:
            _write_runner_state(runs_root, status="round_cap_reached")
    except Exception as e:  # noqa: BLE001
        logger.exception("council crashed: %s", e)
        _write_runner_state(runs_root, status="crashed", error=str(e))
        sys.exit(1)
    finally:
        # Clear STOP so a subsequent /start works without manual cleanup.
        (runs_root / ".STOP").unlink(missing_ok=True)
        _write_runner_state(runs_root, finished_at=datetime.now().isoformat())


def _next_round_id(runs_root: Path, prefix: str = "round") -> str:
    if not runs_root.exists():
        return f"{prefix}_001"
    n = 1
    while True:
        rid = f"{prefix}_{n:03d}"
        round_dir = runs_root / rid
        if not round_dir.exists():
            return rid
        if not (round_dir / "decision.json").exists():
            return rid  # incomplete round — resume it
        n += 1


if __name__ == "__main__":
    main()
