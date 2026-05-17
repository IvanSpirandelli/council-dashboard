/// Widget registry: maps panel_id (and optional kind override) → builder.
///
/// Lookup order on dispatch:
///   1. exact match on (kind, panelId)  — for per-kind UI divergence
///   2. fallback on (null, panelId)     — the default builder for shared panels
///
/// Registration happens once at app boot in `main.dart`:
///
///   registerPanel('corpus_table',
///     (r) => CorpusTablePanel(response: r));
///
///   registerPanel('report_view', kind: 'research',
///     (r) => MarkdownReportPanel(response: r));
library;

import 'package:flutter/widgets.dart';

import 'panel.dart';

class _Key {
  const _Key(this.kind, this.panelId);
  final String? kind;
  final String panelId;

  @override
  bool operator ==(Object other) =>
      other is _Key && other.kind == kind && other.panelId == panelId;
  @override
  int get hashCode => Object.hash(kind, panelId);
}

final Map<_Key, PanelBuilder> _builders = {};

void registerPanel(
  String panelId,
  PanelBuilder builder, {
  String? kind,
}) {
  final key = _Key(kind, panelId);
  if (_builders.containsKey(key)) {
    throw StateError('panel already registered: kind=$kind id=$panelId');
  }
  _builders[key] = builder;
}

PanelBuilder? resolvePanel(String panelId, {String? kind}) {
  return _builders[_Key(kind, panelId)] ?? _builders[_Key(null, panelId)];
}

/// Fallback widget used by the scaffold when no builder is registered
/// for a slot — visible in dev so unregistered panels are obvious.
Widget unknownPanel(PanelResponse r) => Padding(
      padding: const EdgeInsets.all(12),
      child: Text(
        'No widget registered for panel_id=${r.panelId} (slot=${r.slotId})',
      ),
    );
