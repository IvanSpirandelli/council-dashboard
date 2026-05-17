"""CouncilProvider: per-kind declaration of pages → panel slots.

Composition primitive. A kind subclass declares:
- which panels show up on which scaffold page,
- any kind-level static metadata (display name, default sort key, etc.).

Providers do NOT fetch data themselves — they declare the slots, and the
scaffold dispatches each slot to the corresponding `Panel.fetch()`. This
keeps panels reusable across kinds (a `CorpusTablePanel` shows up in
both `mlp_trainer` and `gnn_trainer` with different configs).
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import Any

from council_dashboard.scaffold.panels import PageId, PanelSpec


@dataclass(frozen=True)
class KindInfo:
    kind: str
    display_name: str
    description: str = ""


class CouncilProvider(ABC):
    """Declarative layout for one council kind.

    Subclasses populate :meth:`info` and :meth:`page_layout`. The scaffold
    instantiates one provider per kind (not per council) and reuses it
    across councils that share the kind.
    """

    @abstractmethod
    def info(self) -> KindInfo: ...

    @abstractmethod
    def page_layout(
        self,
        *,
        page: PageId,
        manifest: dict[str, Any],
    ) -> list[PanelSpec]:
        """Return the ordered panel slots that compose ``page`` for this kind.

        The manifest is passed so layouts can react to council-specific
        manifest fields (e.g. an ML-trainer council with ``corpus: gnns``
        configures its corpus panel differently from ``corpus: mlps``).
        """
