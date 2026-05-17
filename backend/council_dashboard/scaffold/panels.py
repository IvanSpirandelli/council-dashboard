"""Panel contracts shared by every council kind.

A *panel* is the unit of UI: backend produces typed JSON, frontend has a
matching registered widget that knows how to render it. Panels are the
composition primitive — kinds are just lists of `PanelSpec` plus their
configs. The same panel id may appear on multiple pages or multiple
times within a page with different configs (e.g. two corpus tables for
two metrics).

Every panel response carries:
- ``panel_id``: stable string the frontend uses to pick a widget.
- ``props``: panel-specific payload (the frontend widget knows the shape).
- ``meta``: scaffold-level info (title, subtitle, refreshable, etc.).

Backends MUST NOT branch on council name inside a panel; the panel is
generic, the *kind* config supplies the parameters.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Protocol, runtime_checkable


# Which scaffold page a panel slot is rendered on.
PageId = str  # "top" | "full" | "info" — kept as str to allow custom pages later.

PAGE_TOP: PageId = "top"
PAGE_FULL: PageId = "full"
PAGE_INFO: PageId = "info"


@dataclass(frozen=True)
class PanelSpec:
    """Declarative slot in a kind's page layout.

    The ``panel_id`` resolves to a panel implementation registered by the
    scaffold; ``config`` is the static, per-slot parameterization (e.g.
    ``{"family": "gnns"}``). ``slot_id`` disambiguates two slots that share
    the same panel_id within one page.
    """

    panel_id: str
    slot_id: str
    config: dict[str, Any] = field(default_factory=dict)


@dataclass(frozen=True)
class PanelResponse:
    panel_id: str
    slot_id: str
    title: str
    subtitle: str | None
    props: dict[str, Any]  # panel-specific; shape contract lives with the panel impl
    meta: dict[str, Any] = field(default_factory=dict)


@runtime_checkable
class Panel(Protocol):
    """Server-side panel impl. One instance per registered panel_id."""

    panel_id: str

    def fetch(
        self,
        *,
        council_name: str,
        manifest: dict[str, Any],
        slot: PanelSpec,
    ) -> PanelResponse: ...
