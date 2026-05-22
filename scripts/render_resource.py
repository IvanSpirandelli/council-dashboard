#!/usr/bin/env python3
"""Render the body of a single generated council resource, as JSON.

The dashboard's "input bar" surfaces generated resources (kind: generated
in topology) that are produced at render-time rather than read from
disk — e.g. ``catalog``, ``gnn_catalog``, ``models_corpus``,
``feature_signal``. Tapping such a tile in the UI hits the
``/councils/{name}/nodes/{node_id}/rendered`` endpoint which shells out
to this script.

Usage:

    render_resource.py \\
        --manifest /path/to/manifest.yaml \\
        --ml-trainer-repo /path/to/ml-trainer \\
        --node-id catalog

The node id must match a ``ResourceBundle`` attribute. Returns
``{"node_id": ..., "body": "..."}`` on success, or
``{"node_id": ..., "error": ...}`` with exit code 2 if the attribute
doesn't exist or isn't a string.

This deliberately does not use ``load_manifest`` — that path is heavier
than we need (validates the entire topology, etc.) and we only require
``resources_dir`` to bootstrap a ``ResourceBundle``.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--ml-trainer-repo", type=Path, required=True)
    parser.add_argument("--node-id", required=True)
    args = parser.parse_args()

    sys.path.insert(0, str(args.ml_trainer_repo.resolve()))

    import yaml
    from ml_trainer.council.resources_loader import ResourceBundle

    manifest_path = args.manifest.resolve()
    with manifest_path.open() as fh:
        body = yaml.safe_load(fh)
    base_dir = manifest_path.parent
    resources_dir = (base_dir / body.get("resources_dir", "resources")).resolve()
    bundle = ResourceBundle(resources_dir=resources_dir)

    if not hasattr(bundle, args.node_id):
        print(json.dumps({
            "node_id": args.node_id,
            "error": f"no rendered resource named {args.node_id!r}",
        }))
        return 2

    rendered = getattr(bundle, args.node_id)
    if not isinstance(rendered, str):
        print(json.dumps({
            "node_id": args.node_id,
            "error": (
                f"resource {args.node_id!r} did not render to text "
                f"(got {type(rendered).__name__})"
            ),
        }))
        return 2

    print(json.dumps({"node_id": args.node_id, "body": rendered}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
