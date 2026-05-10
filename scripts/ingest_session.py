#!/usr/bin/env python3
"""Dump a council session as a single JSON snapshot.

Useful for sharing a frozen view of a session, or for the frontend to
load when the live backend isn't running.

Usage:
    uv run python scripts/ingest_session.py /abs/path/to/runs/council_session_X > snapshot.json
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

# Allow running this script standalone without installing the backend.
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "backend"))

from council_dashboard import ingest  # noqa: E402
from council_dashboard.topology import topology_dict  # noqa: E402


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("session_dir", type=Path)
    ap.add_argument("--include-rounds", action="store_true",
                    help="Include the full per-round detail (decision + runs + LLM calls).")
    args = ap.parse_args()

    session_dir = args.session_dir.expanduser()
    if not session_dir.is_dir():
        print(f"not a directory: {session_dir}", file=sys.stderr)
        sys.exit(1)

    runs_root = session_dir.parent
    summary = ingest.session_summary(runs_root, session_dir.name)
    if summary is None:
        print(f"could not summarize session: {session_dir}", file=sys.stderr)
        sys.exit(1)

    overlay = ingest.topology_overlay(summary)
    snapshot = {
        "topology": topology_dict(),
        "topology_overlay": overlay,
        "session": summary,
    }
    if args.include_rounds:
        rounds_full: list[dict] = []
        for r in summary["rounds"]:
            detail = ingest.round_detail(session_dir, r["round_id"])
            if detail is not None:
                rounds_full.append(detail)
        snapshot["rounds_full"] = rounds_full
    json.dump(snapshot, sys.stdout, indent=2, default=str)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
