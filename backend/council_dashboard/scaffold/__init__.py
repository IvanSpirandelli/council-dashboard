"""Scaffold: shared contracts that every council kind plugs into."""

from council_dashboard.scaffold.panels import (
    PAGE_FULL,
    PAGE_INFO,
    PAGE_TOP,
    PageId,
    Panel,
    PanelResponse,
    PanelSpec,
)
from council_dashboard.scaffold.provider import CouncilProvider, KindInfo
from council_dashboard.scaffold.registry import (
    PANELS,
    PROVIDERS,
    register_panel,
    register_provider,
    resolve_panel,
    resolve_provider,
)

__all__ = [
    "PAGE_FULL",
    "PAGE_INFO",
    "PAGE_TOP",
    "PageId",
    "Panel",
    "PanelResponse",
    "PanelSpec",
    "CouncilProvider",
    "KindInfo",
    "PANELS",
    "PROVIDERS",
    "register_panel",
    "register_provider",
    "resolve_panel",
    "resolve_provider",
]
