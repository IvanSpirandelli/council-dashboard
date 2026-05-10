"""Settings loaded from environment / .env."""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

from dotenv import load_dotenv

load_dotenv()


def _env_path(name: str, default: str) -> Path:
    return Path(os.environ.get(name, default)).expanduser()


@dataclass(frozen=True)
class Settings:
    runs_root: Path
    models_root: Path
    ml_trainer_repo: Path
    host: str
    port: int

    @classmethod
    def load(cls) -> "Settings":
        return cls(
            runs_root=_env_path(
                "ML_TRAINER_RUNS_ROOT",
                "/Users/ivanspirandelli/a-project-called-life/code-projects/agentic-docking/ml-trainer/runs",
            ),
            models_root=_env_path(
                "ML_TRAINER_MODELS_ROOT",
                "/Users/ivanspirandelli/a-project-called-life/code-projects/agentic-docking/ml-trainer/models",
            ),
            ml_trainer_repo=_env_path(
                "ML_TRAINER_REPO",
                "/Users/ivanspirandelli/a-project-called-life/code-projects/agentic-docking/ml-trainer",
            ),
            host=os.environ.get("DASHBOARD_HOST", "127.0.0.1"),
            port=int(os.environ.get("DASHBOARD_PORT", "8765")),
        )
