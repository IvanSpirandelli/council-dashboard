# council-dashboard

Dashboard for the **agentic-docking ml-trainer council**: visualize all
agents, their connections, token usage, prompts/responses; trace the
context behind each round's decisions; start, stop, and resume a council
session; view the resulting model-performance table.

The council itself lives in `../agentic-docking/ml-trainer/`. This repo
is read-mostly: it watches a chosen `runs_root` directory on disk, and
controls a long-running council subprocess.

## Layout

```
backend/                 FastAPI app, ingestion library, process supervisor
  council_dashboard/
    api.py               FastAPI app + routes
    ingest.py            Pure-Python parsers (sessions, rounds, llm calls)
    topology.py          Static agent-graph definition
    supervisor.py        Start / stop / resume the council subprocess
    config.py            Settings (paths, ports, ml-trainer location)
  pyproject.toml
frontend/                Flutter web/desktop app
  lib/
    main.dart
    api/                 Backend client
    models/              JSON-deserialized records
    pages/               SessionList, SessionDetail, RoundDetail, ...
    widgets/             AgentGraph, LLMCallPanel, MetricsTable, ...
scripts/                 One-off Python entry points (CLI)
  ingest_session.py      Parse a runs_root → JSON snapshot (offline)
  performance_table.py   Wraps ml-trainer's council_table.py for the dashboard
  launch_council.py      Wrapped runner that exposes graceful stop
docs/
  ARCHITECTURE.md        Design notes + Socratic iteration log
```

## Quick start

```bash
# Backend
cd backend
uv sync
uv run uvicorn council_dashboard.api:app --reload --port 8765

# Frontend
cd frontend
flutter run -d chrome
```

The backend reads sessions from
`$ML_TRAINER_RUNS_ROOT` (default
`../agentic-docking/ml-trainer/runs`) and finds `models/mlps/` under
`$ML_TRAINER_MODELS_ROOT`. Override via the `.env` file in `backend/`.

## What you can do

- **Sessions** — list every `council_*` run under `runs_root`, see round
  count + status (running / stopped / completed).
- **Rounds** — per round: agent topology with each LLM call's wall-clock
  duration and approximate token count (computed from prompt / response
  byte lengths; the upstream `ClaudeCodeLLM` does not log exact usage).
  Click an agent to view the prompt and the structured response.
- **Performance table** — calls into `ml-trainer/scripts/council_table.py`
  and renders the result.
- **Control** — start a new session against a target `runs_root`, stop
  the current run gracefully (after the current round finishes), resume
  by re-launching against the existing `runs_root`.

## What it deliberately does NOT do

- Does not modify any council code — the dashboard is a read-side and a
  process supervisor.
- Does not re-implement metric aggregation; uses
  `ml-trainer/scripts/council_table.py` as the source of truth.
- Does not store its own database; everything is parsed live from disk.

See `docs/ARCHITECTURE.md` for design rationale.
