#!/usr/bin/env python3
"""Wrapper around ml-trainer's ``scripts/council_table.py``.

Adds a ``--json`` mode that emits structured rows the dashboard frontend
can render directly. The text mode falls through to the upstream script
unchanged so anyone running this from a shell sees the same output.

Usage:
    uv run python scripts/performance_table.py --json
    uv run python scripts/performance_table.py --json --session /abs/path/to/session
    uv run python scripts/performance_table.py --json --sort bdb --models-root /abs/models
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path


def _import_upstream(ml_trainer_repo: Path):
    """Import ml-trainer's ``scripts/council_table.py`` as a module."""
    scripts_dir = ml_trainer_repo / "scripts"
    if not scripts_dir.is_dir():
        raise FileNotFoundError(f"ml-trainer scripts dir not found: {scripts_dir}")
    sys.path.insert(0, str(scripts_dir))
    import council_table  # noqa: E402

    return council_table


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--ml-trainer-repo",
        default=os.environ.get(
            "ML_TRAINER_REPO",
            "/Users/ivanspirandelli/a-project-called-life/code-projects/agentic-docking/ml-trainer",
        ),
        help="Path to the ml-trainer repo (must contain scripts/council_table.py).",
    )
    parser.add_argument("--models-root", default=None, help="Override models/mlps location.")
    parser.add_argument("--session", default=None, help="Absolute session dir to filter to.")
    parser.add_argument("--round", default=None, help="Single round id within --session.")
    parser.add_argument("--sort", default="cl2")
    parser.add_argument("--asc", action="store_true")
    parser.add_argument("--all-variants", action="store_true")
    parser.add_argument("--json", action="store_true", help="Emit JSON instead of a text table.")
    args = parser.parse_args()

    ml_trainer_repo = Path(args.ml_trainer_repo).expanduser()
    upstream = _import_upstream(ml_trainer_repo)

    models_root = Path(
        args.models_root
        or os.environ.get("ML_TRAINER_MODELS_ROOT", str(ml_trainer_repo / "models"))
    )
    if (models_root / "mlps").is_dir():
        models_root = models_root / "mlps"
    if not models_root.exists():
        print(f"models root not found: {models_root}", file=sys.stderr)
        sys.exit(1)

    session_dir = Path(args.session) if args.session else None
    session_index: dict[str, str] = {}
    if session_dir is not None:
        if not session_dir.exists():
            print(f"session directory not found: {session_dir}", file=sys.stderr)
            sys.exit(1)
        session_index = upstream.load_session_index(session_dir, args.round)

    rows = upstream.load_all_mlps(
        models_root,
        session_index,
        round_filter=args.round,
        standard_only=not args.all_variants,
    )

    if args.sort not in upstream.SORT_ALIASES:
        print(
            f"unknown sort key: {args.sort}; choose from {sorted(upstream.SORT_ALIASES)}",
            file=sys.stderr,
        )
        sys.exit(2)
    sort_key = upstream.SORT_ALIASES[args.sort]

    def sort_val(row: dict):
        v = row.get(sort_key + "_mean") if sort_key != "__fp__" else row["__fp__"]
        return (v is None, v if v is not None else "")

    rows = sorted(rows, key=sort_val, reverse=not args.asc)

    if args.json:
        # Strip leading-underscore convention for cleaner JSON keys.
        clean_rows: list[dict] = []
        for r in rows:
            clean_rows.append(
                {
                    "fingerprint": r["__fp__"],
                    "round": r["__round__"],
                    "surface": r["__surface__"],
                    "seeds": r["__seeds__"],
                    "features": r["__feats__"],
                    "hidden": r["__hidden__"],
                    "lr": r["__lr__"],
                    "dropout": r["__do__"],
                    **{k: v for k, v in r.items() if not k.startswith("__")},
                }
            )
        json.dump(
            {
                "rows": clean_rows,
                "sort": args.sort,
                "ascending": args.asc,
                "metrics": [
                    {"label": label, "key": key, "alias": alias}
                    for label, key, alias in upstream.METRICS
                ],
                "session": str(session_dir) if session_dir else None,
                "round": args.round,
            },
            sys.stdout,
        )
        sys.stdout.write("\n")
        return

    upstream.print_table(
        rows,
        sort_key,
        ascending=args.asc,
        show_std=False,
        show_round=bool(session_dir),
    )


if __name__ == "__main__":
    main()
