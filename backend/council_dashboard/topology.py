"""Static agent topology for the 5-seat council.

The council's per-round seats and information edges are stable enough
to encode once. The frontend overlays per-round LLM-call data (counts,
token approximations, latencies) on top of this skeleton.

Seats:
  - empirical_analyst   (LLM)  proposes specs grounded in corpus history
  - theoretical_analyst (LLM)  proposes specs from theoretical priors
  - validator           (code) attaches constraint flags pre-decider
  - decider             (LLM)  picks promoted candidates + may re-prompt
  - master_critic       (LLM)  reviews candidates + decision; may force re-prompt
  - executor            (code) trains promoted specs, writes runs.jsonl
  - feature_developer   (LLM)  on-demand only; not invoked per round

Edges describe the information flow in a single round.
"""

from __future__ import annotations

from typing import Literal, TypedDict

NodeKind = Literal["llm", "code"]


class Node(TypedDict):
    id: str
    label: str
    kind: NodeKind
    role: str
    # Static layout coordinates (0..1) — the frontend's CustomPainter
    # multiplies by canvas size. Picked once so the diagram is readable.
    x: float
    y: float


class Edge(TypedDict):
    src: str
    dst: str
    label: str


NODES: list[Node] = [
    {
        "id": "empirical_analyst",
        "label": "Empirical Analyst",
        "kind": "llm",
        "role": "Proposes ExperimentSpecs grounded in the corpus + active anchors.",
        "x": 0.10,
        "y": 0.20,
    },
    {
        "id": "theoretical_analyst",
        "label": "Theoretical Analyst",
        "kind": "llm",
        "role": "Proposes ExperimentSpecs driven by theoretical priors / unexplored axes.",
        "x": 0.10,
        "y": 0.65,
    },
    {
        "id": "validator",
        "label": "Validator",
        "kind": "code",
        "role": "Attaches hard/soft constraint flags + corpus-duplicate detection.",
        "x": 0.40,
        "y": 0.42,
    },
    {
        "id": "decider",
        "label": "Decider",
        "kind": "llm",
        "role": "Selects promoted candidates; emits stop_signal + new_questions.",
        "x": 0.65,
        "y": 0.20,
    },
    {
        "id": "master_critic",
        "label": "Master Critic",
        "kind": "llm",
        "role": "Reviews candidates + decision; may force one re-prompt cycle.",
        "x": 0.65,
        "y": 0.65,
    },
    {
        "id": "executor",
        "label": "Executor",
        "kind": "code",
        "role": "Trains promoted specs; writes runs.jsonl with metrics + artifacts.",
        "x": 0.92,
        "y": 0.42,
    },
]

EDGES: list[Edge] = [
    {"src": "empirical_analyst", "dst": "validator", "label": "candidates"},
    {"src": "theoretical_analyst", "dst": "validator", "label": "candidates"},
    {"src": "validator", "dst": "decider", "label": "candidates + flags"},
    {"src": "validator", "dst": "master_critic", "label": "candidates"},
    {"src": "decider", "dst": "master_critic", "label": "promoted set"},
    {"src": "master_critic", "dst": "decider", "label": "re_prompt (turn 2)"},
    {"src": "decider", "dst": "executor", "label": "promoted specs"},
]


def topology_dict() -> dict:
    """JSON-serializable snapshot for the frontend."""
    return {"nodes": list(NODES), "edges": list(EDGES)}
