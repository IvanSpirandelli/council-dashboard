#!/usr/bin/env python3
"""Render the system + user prompt for one council agent, as JSON.

Two modes:

(1) From an on-disk manifest:

    render_preview.py \
        --manifest /path/to/manifest.yaml \
        --agent-id empirical_analyst \
        --ml-trainer-repo /path/to/ml-trainer \
        [--extra-context "..."]

(2) From a manifest body piped on stdin (council-dir anchors relative paths):

    cat manifest.yaml | render_preview.py \
        --council-dir /path/to/ml_trainer/council \
        --agent-id empirical_analyst \
        --ml-trainer-repo /path/to/ml-trainer

Output (stdout, JSON):

    {
      "agent": {...manifest agent block...},
      "system_prompt": "...",
      "user_prompt": "...",
      "schema_name": "CANDIDATES_SCHEMA"
    }
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


# Runtime-only template variables (populated at call time, never on preview).
PREVIEW_TEMPLATE_VARS = {
    "candidate_blocks": (
        "(placeholder — at call time this becomes one block per candidate "
        "with experiment_id, proposer, and the spec dump)"
    ),
    "decider_submission": (
        "(placeholder — at call time this becomes the decider's "
        "promoted_ids + rationale)"
    ),
    "runtime_ctx": (
        "(placeholder — at call time: round_id=... | rounds_remaining=... "
        "| cost_cap_active=... | best_so_far=... | re_prompt_turn=... "
        "| max_promotions=... | max_critic_turns=...)"
    ),
    "turn": "<turn>",
    "max_critic_turns": "<max_critic_turns>",
}


def main() -> int:
    parser = argparse.ArgumentParser()
    src = parser.add_mutually_exclusive_group(required=True)
    src.add_argument(
        "--manifest", type=Path,
        help="Path to manifest.yaml on disk (mode 1).",
    )
    src.add_argument(
        "--council-dir", type=Path,
        help="Council directory; manifest body is read from stdin (mode 2).",
    )
    parser.add_argument("--agent-id", required=True)
    parser.add_argument("--ml-trainer-repo", required=True, type=Path)
    parser.add_argument("--extra-context", default=None)
    args = parser.parse_args()

    sys.path.insert(0, str(args.ml_trainer_repo.resolve()))

    from ml_trainer.council.agent_runtime import (
        load_manifest,
        load_manifest_from_dict,
        render_system_prompt,
        render_user_prompt,
    )
    from ml_trainer.council.resources_loader import ResourceBundle
    import yaml

    if args.manifest is not None:
        manifest = load_manifest(args.manifest)
    else:
        body = yaml.safe_load(sys.stdin.read())
        manifest = load_manifest_from_dict(body, base_dir=args.council_dir)

    agent = manifest.agent(args.agent_id)
    bundle = ResourceBundle(resources_dir=manifest.resources_dir)

    system_prompt = render_system_prompt(manifest, agent)
    user_prompt = render_user_prompt(
        agent,
        bundle,
        history=[],
        extra_context=args.extra_context,
        template_vars=PREVIEW_TEMPLATE_VARS,
    )

    out = {
        "agent": {
            "id": agent.id,
            "role": agent.role,
            "prompt": agent.prompt,
            "model": agent.model,
            "schema": agent.schema,
            "n_candidates": agent.n_candidates,
            "history_window": agent.history_window,
        },
        "system_prompt": system_prompt,
        "user_prompt": user_prompt,
        "schema_name": agent.schema,
    }
    print(json.dumps(out, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
