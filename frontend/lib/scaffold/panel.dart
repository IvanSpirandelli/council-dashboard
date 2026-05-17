/// Panel widget contract.
///
/// A `Panel` is a widget that knows how to render one `PanelResponse`
/// from the backend. Panels are registered by `panel_id` in
/// `kind_registry.dart`. The scaffold page shells (TopResultsShell etc.)
/// fetch the layout, then for each slot ask the registry for the
/// matching `PanelBuilder` and hand it the slot's data.
///
/// Per-kind UI divergence happens *here*: same backend panel_id can
/// resolve to different widgets if registered under different kinds.
/// In practice most panels are shared (e.g. `corpus_table`), so the
/// registry is keyed primarily by `panel_id` with optional per-kind
/// override.
library;

import 'package:flutter/widgets.dart';

/// JSON contract returned by `GET /councils/{name}/scaffold/slots/{slot_id}`.
class PanelResponse {
  const PanelResponse({
    required this.panelId,
    required this.slotId,
    required this.title,
    required this.props,
    this.subtitle,
    this.meta = const {},
  });

  final String panelId;
  final String slotId;
  final String title;
  final String? subtitle;
  final Map<String, dynamic> props;
  final Map<String, dynamic> meta;

  factory PanelResponse.fromJson(Map<String, dynamic> j) => PanelResponse(
        panelId: j['panel_id'] as String,
        slotId: j['slot_id'] as String,
        title: j['title'] as String,
        subtitle: j['subtitle'] as String?,
        props: (j['props'] as Map?)?.cast<String, dynamic>() ?? const {},
        meta: (j['meta'] as Map?)?.cast<String, dynamic>() ?? const {},
      );
}

/// Static description of a slot, returned by
/// `GET /councils/{name}/scaffold/layout`. The frontend only needs
/// `panelId` + `slotId` to dispatch and fetch; `config` is opaque (the
/// backend already applied it when generating the response).
class PanelSpec {
  const PanelSpec({required this.panelId, required this.slotId});

  final String panelId;
  final String slotId;

  factory PanelSpec.fromJson(Map<String, dynamic> j) => PanelSpec(
        panelId: j['panel_id'] as String,
        slotId: j['slot_id'] as String,
      );
}

/// A builder that turns a fetched `PanelResponse` into a widget.
///
/// Kept as a typedef rather than an abstract class so panel widgets can
/// stay regular `StatelessWidget` / `ConsumerWidget` constructors —
/// registration is just a `(response) => MyPanel(response: response)`.
typedef PanelBuilder = Widget Function(PanelResponse response);
