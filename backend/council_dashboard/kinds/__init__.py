"""Concrete council kinds. Each module registers panels + a provider.

Wiring: ``api.py`` calls ``bootstrap(models_root=...)`` once at app
startup, which idempotently registers every shipped kind. New kinds add
one ``register_*`` call here and one ``kinds/<name>.py`` module —
nothing else.
"""

from __future__ import annotations

from pathlib import Path

from council_dashboard.kinds import ml_trainer


def bootstrap(*, models_root: Path) -> None:
    ml_trainer.register_ml_trainer(models_root=models_root)
