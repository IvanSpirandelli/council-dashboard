/// Renders a `corpus_table` PanelResponse.
///
/// Shared by MLP and GNN ml-trainer councils. Row-projection logic that
/// used to live duplicated in council_home_page.dart + performance_page.dart
/// is consolidated here.
library;

import 'package:flutter/material.dart';

import '../../scaffold/panel.dart';
import '../../widgets/results_table.dart';

class CorpusTablePanel extends StatelessWidget {
  const CorpusTablePanel({super.key, required this.response});

  final PanelResponse response;

  @override
  Widget build(BuildContext context) {
    final rows = ((response.props['rows'] as List?) ?? const [])
        .cast<Map<String, dynamic>>();
    final nTotal = response.props['n_total'] as int? ?? rows.length;
    final family = response.props['family'] as String? ?? 'mlps';

    return Card(
      margin: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            title: Text(response.title),
            subtitle: Text('${response.subtitle ?? ''}  ·  family: $family'),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: rows.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(child: Text('No models in corpus yet.')),
                  )
                : ResultsTable(
                    idLabel: 'fingerprint',
                    emptyMessage: 'No models in corpus.',
                    rows: [
                      for (final r in rows)
                        ResultRow(
                          id: r['fingerprint']?.toString() ?? '',
                          cl2: _num(r['test_pearson_r_mean']),
                          bdb: _num(r['bdb2020_pearson_r_mean']),
                          egfr: _num(r['egfr_pearson_r_mean']),
                          mpro: _num(r['mpro_pearson_r_mean']),
                          featureIds: _splitFeatureIds(r['feature_ids']),
                          architecture: _architecture(r),
                        ),
                    ],
                  ),
          ),
          if (rows.isNotEmpty && rows.length < nTotal)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Text(
                'Showing ${rows.length} of $nTotal',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }

  static num? _num(Object? v) => v is num ? v : null;

  // Backend serializes feature_ids as a comma-joined string for both
  // families. GNN entries are pre-prefixed (vtx:foo, tri:bar, …) by the
  // backend so the chip styling reads as a taxonomy without extra logic
  // here.
  static List<String> _splitFeatureIds(Object? v) {
    if (v is List) return [for (final f in v) f.toString()];
    if (v is String && v.isNotEmpty) {
      return [for (final f in v.split(',')) if (f.isNotEmpty) f];
    }
    return const [];
  }

  static String _architecture(Map<String, dynamic> r) {
    final hidden = r['hidden']?.toString() ?? '?';
    final dropout = r['dropout'];
    if (dropout is num) {
      return '$hidden · d=${dropout.toStringAsFixed(2)}';
    }
    return hidden;
  }
}
