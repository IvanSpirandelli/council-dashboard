"""ML-trainer council kind: MLP + GNN sub-flavors via manifest config.

Single kind, multiple sub-flavors. The manifest declares::

    kind: ml_trainer
    corpus: mlps   # or "gnns"

…and this provider configures its corpus panel accordingly. Adding a
new ML-family flavor (e.g. a new corpus layout) doesn't require a new
kind — only a new ``corpus:`` value handled by the existing performance
reader.

Sketch only — the panel ``fetch()`` delegates to the existing
:mod:`council_dashboard.performance` module so we don't fork logic.
"""

from __future__ import annotations

from pathlib import Path
from typing import Any

from council_dashboard import performance
from council_dashboard.scaffold import (
    PAGE_FULL,
    PAGE_TOP,
    CouncilProvider,
    KindInfo,
    PageId,
    Panel,
    PanelResponse,
    PanelSpec,
    register_panel,
    register_provider,
)


class CorpusTablePanel:
    """Generic corpus → ranked table panel. Reused across ML kinds.

    config keys:
      family: "mlps" | "gnns"           (which corpus root to scan)
      sort:   metric column name        (default "test_pearson_r_mean")
      limit:  optional int              (None = all)
    """

    panel_id = "corpus_table"

    def __init__(self, *, models_root: Path) -> None:
        self.models_root = models_root

    def fetch(
        self,
        *,
        council_name: str,
        manifest: dict[str, Any],
        slot: PanelSpec,
    ) -> PanelResponse:
        cfg = slot.config
        family = str(cfg.get("family") or manifest.get("corpus") or "mlps")
        sort = str(cfg.get("sort") or "test_pearson_r_mean")
        limit = cfg.get("limit")
        # Query-string overrides arrive as strings; accept "true"/"1"/etc.
        raw_asc = cfg.get("ascending", False)
        ascending = (
            raw_asc.lower() in ("1", "true", "yes")
            if isinstance(raw_asc, str)
            else bool(raw_asc)
        )

        payload = performance.performance_payload(
            self.models_root,
            family=family,
            sort=sort,
            ascending=ascending,
            limit=int(limit) if limit else None,
        )
        return PanelResponse(
            panel_id=self.panel_id,
            slot_id=slot.slot_id,
            title=cfg.get("title", "Top performers" if limit else "Full results"),
            subtitle=f"{payload['n_total']} models in corpus",
            props={
                "rows": payload["rows"],
                "n_total": payload["n_total"],
                "family": payload["family"],
                "sort": payload["sort"],
                "ascending": payload["ascending"],
                # Taxonomy hint: frontend can branch chip rendering on this.
                "taxonomy": "gnn_channels" if family == "gnns" else "feature_ids",
            },
            meta={"refreshable": True},
        )


class MLTrainerProvider(CouncilProvider):
    """One kind for both MLP and GNN trainer councils."""

    def info(self) -> KindInfo:
        return KindInfo(
            kind="ml_trainer",
            display_name="ML trainer council",
            description="Trains a model family against a corpus; ranks by test metric.",
        )

    def page_layout(
        self, *, page: PageId, manifest: dict[str, Any]
    ) -> list[PanelSpec]:
        # The manifest's `corpus:` carries the MLP vs GNN switch; the
        # CorpusTablePanel reads it via slot config fallback.
        family = manifest.get("corpus") or "mlps"
        if page == PAGE_TOP:
            return [
                PanelSpec(
                    panel_id="corpus_table",
                    slot_id="top",
                    config={"family": family, "limit": 10, "title": "Top performers"},
                ),
            ]
        if page == PAGE_FULL:
            return [
                PanelSpec(
                    panel_id="corpus_table",
                    slot_id="full",
                    config={"family": family, "title": "Full results"},
                ),
            ]
        # PAGE_INFO: manifest/topology/resources panels would slot here once
        # they're refactored from the current pages into Panel impls.
        return []


def register_ml_trainer(*, models_root: Path) -> None:
    """Idempotent registration hook. Called once at app startup."""
    register_panel(CorpusTablePanel(models_root=models_root))
    register_provider(MLTrainerProvider())
