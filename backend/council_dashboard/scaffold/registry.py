"""Kind + panel registries.

Two side-by-side registries, both populated at import time by the
``kinds/`` package:

- :data:`PANELS` — ``panel_id`` → :class:`Panel` instance. Panels are
  shared across kinds; a `corpus_table` panel is registered once and
  reused by every kind that wants it.
- :data:`PROVIDERS` — ``kind`` → :class:`CouncilProvider` instance.
  Each manifest's ``kind:`` field resolves to one provider here.

Keeping these flat (no inheritance tree) is deliberate. Kinds compose by
declaring panel slots, not by extending each other. A "thin parent" with
shared corpus-fetching helpers is fine *inside* a panel module (e.g.
``MLTrainerCorpusReader``), but the provider classes themselves stay
sibling-flat for predictable dispatch.
"""

from __future__ import annotations

from council_dashboard.scaffold.panels import Panel
from council_dashboard.scaffold.provider import CouncilProvider

PANELS: dict[str, Panel] = {}
PROVIDERS: dict[str, CouncilProvider] = {}


def register_panel(panel: Panel) -> None:
    if panel.panel_id in PANELS:
        raise ValueError(f"panel already registered: {panel.panel_id!r}")
    PANELS[panel.panel_id] = panel


def register_provider(provider: CouncilProvider) -> None:
    info = provider.info()
    if info.kind in PROVIDERS:
        raise ValueError(f"kind already registered: {info.kind!r}")
    PROVIDERS[info.kind] = provider


def resolve_provider(kind: str) -> CouncilProvider:
    if kind not in PROVIDERS:
        raise KeyError(
            f"unknown council kind: {kind!r}. Registered: {sorted(PROVIDERS)}"
        )
    return PROVIDERS[kind]


def resolve_panel(panel_id: str) -> Panel:
    if panel_id not in PANELS:
        raise KeyError(
            f"unknown panel id: {panel_id!r}. Registered: {sorted(PANELS)}"
        )
    return PANELS[panel_id]
