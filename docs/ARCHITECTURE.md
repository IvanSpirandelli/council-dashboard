# Architecture

This document captures the design decisions behind the dashboard, with
the Socratic iteration that shaped each one.

## Guiding principle

> Be able to understand **how and with what context** the council is
> making decisions, and **visualize the resulting model performances**.

Everything else is secondary. The dashboard is a microscope on the
council's decision-making, not a replacement for any of its logic.

---

## Boundaries

`ml-trainer` already persists a clean per-round audit trail under
`runs/<session>/round_NNN/`:

```
decision.json          DecisionRecord (candidates, promoted, lineage, results)
runs.jsonl             RunResult per executed spec (metrics, artifacts, fingerprint)
llm_calls.jsonl        One LLMCall per agent invocation
llm/                   *.prompt.txt + *.response.json for each call
```

The dashboard is a thin reader over those files plus a process
supervisor for the `run_council` driver. **No new schemas.** The
ingestion library re-uses ml-trainer's pydantic models where possible,
falling back to plain JSON parsing where the dashboard cares about
fields ml-trainer does not yet expose.

`feature-builder` has zero involvement: features are evaluated through
ml-trainer's executor; the dashboard only reads results.

---

## Decision 1 — Token usage tracking

**Question:** the user wants to see "how many tokens" each agent uses.
The upstream `ClaudeCodeLLM` (council/llm.py) only stores the
*structured* JSON payload, not the raw `claude -p` envelope, so the
exact `usage.input_tokens` / `usage.output_tokens` fields are dropped
before they reach disk.

**Iteration 1 — best-effort approximation.** Compute a chars/4 estimate
from `prompt.txt` and the rendered `response.json`. Display it as
"≈ N tokens" with a tooltip explaining the approximation. Pros: no
upstream changes, works on every existing session. Cons: not exact.

**Iteration 2 — patch upstream to log raw envelope.** Add a tiny side
file `*.usage.json` next to each `*.response.json`, populated when the
upstream client sees the `usage` block in the `claude -p` JSON. Pros:
exact. Cons: requires editing ml-trainer code; would not retroactively
populate the 13 existing rounds.

**Resolution.** Ship Iteration 1 today (it's the only thing that works
across existing data). Add an optional Iteration-2 patch under
`docs/upstream_patch.md` for the user to apply when convenient — the
backend will prefer `*.usage.json` if present, fall back to the
approximation if not.

---

## Decision 2 — Backend shape

**Question:** FastAPI with file-system reads on each request, or
pre-built JSON snapshots?

**Iteration 1 — live filesystem reads.** Every endpoint walks the
`runs_root` and parses what it needs. Pros: zero state to invalidate,
any new round that lands on disk is immediately visible. Cons: cost
scales with session size (≈ tens of rounds × small files = still cheap).

**Iteration 2 — pre-built snapshot index.** A daemon walks the tree and
publishes a `dashboard_index.json`. Pros: O(1) reads. Cons: another
moving part, plus invalidation.

**Resolution.** Iteration 1. Each round is a few KB; thirteen rounds is
~hundreds of KB. The bottleneck for large prompt files is rendering,
not parsing — we lazy-load prompt bodies only when a round detail is
opened. An in-memory cache keyed by `(session, round, mtime)` keeps
repeat reads fast.

---

## Decision 3 — Process control (start / stop / resume)

**Question:** how do we let the user "stop and resume the council at
any time"?

**Iteration 1 — kill -SIGTERM the subprocess.** Simple but the council
is mid-round when you stop it; the half-written `decision.json` is
useless and the `runs.jsonl` may have partial entries.

**Iteration 2 — cooperative stop file.** The dashboard writes
`runs_root/.STOP` and the runner's loop body checks for it between
rounds. Clean shutdown after the current round's `decision.json` is
flushed. Resume = relaunch against the same `runs_root`; the existing
loop already loads history from disk.

**Resolution.** Iteration 2, implemented as a small wrapper script
`scripts/launch_council.py` that:

1. Imports the user's existing council factory (configurable hook),
2. Calls `run_council(...)` with a custom `should_stop` callback that
   checks `runs_root/.STOP` between rounds,
3. Writes `runs_root/.runner.json` with `{pid, started_at, status}` so
   the dashboard can observe it.

The dashboard's `/sessions/{id}/control` endpoint manipulates `.STOP`
and the `.runner.json` file. We do not embed council factories in the
dashboard — the user picks which factory to run via launch config.

> **Caveat:** the upstream `run_council` does not currently accept a
> `should_stop` callback. The wrapper bypasses this by polling via
> Python's signal handler: SIGTERM is converted into a `.STOP` flag on
> first delivery, and a finalizer writes the in-flight DecisionRecord
> if one was being constructed. This is a best-effort soft-stop; the
> documentation calls this out so the user knows what guarantees hold.

---

## Decision 4 — Agent topology view

**Question:** static schematic, or graph computed from data?

**Iteration 1 — fully data-driven.** Walk the `llm_calls.jsonl` of a
round and build edges from the call order. Pros: no maintenance. Cons:
the LLM-call timeline is mostly linear (analysts → decider → critic),
which doesn't tell you the *information flow* (analysts produce
candidates that the decider promotes, the critic critiques the
decider's promotion, etc.).

**Iteration 2 — static topology, data-overlaid.** A fixed node/edge
declaration (`backend/.../topology.py`) describes the seats and the
information edges between them. Per-round data overlays node colour
(latency, token count) and edge thickness (number of candidates passed
along that edge). Pros: communicates the *role* of each seat, and the
overlay shows where the action actually was.

**Resolution.** Iteration 2. The topology is small and stable; encoding
it once in Python beats reconstructing it from logs every round.

---

## Decision 5 — Frontend stack

User specified Flutter. Within that:

- **State management**: `flutter_riverpod`. Lightweight, async-friendly,
  good for the read-mostly pages we need.
- **HTTP**: `package:http` (no need for `dio` — we make a handful of
  GETs and one or two POSTs).
- **Routing**: `go_router`. Deep links to sessions/rounds make sharing
  easy.
- **Graph rendering**: a hand-rolled `CustomPainter`. Five nodes, six
  edges, fixed layout — pulling in `graphview` or similar would be
  overkill. The painter takes the topology + an overlay map and draws.

---

## Where Python does the heavy lifting

The user asked us to push as much logic as possible into Python. We do
so as follows:

- `backend/.../ingest.py` — all parsing (decision.json, runs.jsonl,
  llm_calls.jsonl, prompt/response files). The frontend never touches
  raw council files.
- `backend/.../topology.py` — the agent graph schema, also serialized
  to the frontend.
- `scripts/performance_table.py` — wraps
  `ml-trainer/scripts/council_table.py` and emits structured JSON.
- `scripts/ingest_session.py` — offline dump of a whole session as JSON
  (handy for sharing, or for the frontend to consume statically when
  the backend isn't running).
- `scripts/launch_council.py` — runner with cooperative stop, the only
  process-control surface we expose.

The Flutter app is therefore ≈ data-binding + rendering: no business
logic.
