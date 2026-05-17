"""Scaffold HTTP routes: layout + per-slot data.

Two endpoints — that's the entire scaffold surface:

  GET /councils/{name}/scaffold/layout?page=top
      → {"kind": "ml_trainer", "page": "top",
         "slots": [{"panel_id": "...", "slot_id": "...", "config": {...}}, ...]}

  GET /councils/{name}/scaffold/slots/{slot_id}?page=top
      → PanelResponse (typed JSON the matching frontend widget consumes)

The frontend's page shells call ``layout`` once to discover slots, then
fan out ``slots/{slot_id}`` calls — one per slot — so panels stay
independently cacheable and refreshable.
"""

from __future__ import annotations

from dataclasses import asdict
from typing import Any

from fastapi import APIRouter, HTTPException, Request

from council_dashboard import councils as councils_mod
from council_dashboard.scaffold.panels import PanelSpec
from council_dashboard.scaffold.registry import resolve_panel, resolve_provider


def build_router(*, councils_root, default_kind: str = "ml_trainer") -> APIRouter:
    router = APIRouter()

    def _manifest_or_404(name: str) -> dict[str, Any]:
        try:
            return councils_mod.read_manifest(councils_root, name)
        except FileNotFoundError as e:
            raise HTTPException(404, str(e))

    @router.get("/councils/{name}/scaffold/layout")
    def layout(name: str, page: str = "top") -> dict[str, Any]:
        manifest = _manifest_or_404(name)
        kind = str(manifest.get("kind") or default_kind)
        provider = resolve_provider(kind)
        slots = provider.page_layout(page=page, manifest=manifest)
        return {
            "kind": kind,
            "page": page,
            "slots": [asdict(s) for s in slots],
        }

    @router.get("/councils/{name}/scaffold/slots/{slot_id}")
    def slot_data(
        request: Request, name: str, slot_id: str, page: str = "top"
    ) -> dict[str, Any]:
        manifest = _manifest_or_404(name)
        kind = str(manifest.get("kind") or default_kind)
        provider = resolve_provider(kind)
        slots = provider.page_layout(page=page, manifest=manifest)
        spec = next((s for s in slots if s.slot_id == slot_id), None)
        if spec is None:
            raise HTTPException(
                404, f"slot {slot_id!r} not declared on page {page!r} for kind {kind!r}"
            )
        # Per-slot config overrides via query string (e.g. ?sort=...&ascending=true).
        # Reserved query keys never overwrite slot config — only unknown
        # keys flow through, so a panel always sees a sensible default.
        reserved = {"page"}
        overrides = {
            k: v for k, v in request.query_params.items() if k not in reserved
        }
        merged = {**spec.config, **overrides}
        merged_spec = PanelSpec(panel_id=spec.panel_id, slot_id=spec.slot_id, config=merged)
        panel = resolve_panel(spec.panel_id)
        return asdict(panel.fetch(council_name=name, manifest=manifest, slot=merged_spec))

    return router
