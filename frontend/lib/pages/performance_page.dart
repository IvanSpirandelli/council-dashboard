import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/providers.dart';
import '../widgets/error_view.dart';
import '../widgets/results_table.dart';

/// Full corpus-derived performance table for one council.
class PerformancePage extends ConsumerStatefulWidget {
  const PerformancePage({super.key, required this.councilName});

  final String councilName;

  @override
  ConsumerState<PerformancePage> createState() => _PerformancePageState();
}

class _PerformancePageState extends ConsumerState<PerformancePage> {
  String _sort = 'test_pearson_r_mean';
  bool _ascending = false;

  static const _sortOptions = <String, String>{
    'test_pearson_r_mean': 'CL2 r',
    'bdb2020_pearson_r_mean': 'BDB r',
    'egfr_pearson_r_mean': 'EGFR r',
    'mpro_pearson_r_mean': 'MPro r',
    'fingerprint': 'fingerprint',
  };

  @override
  Widget build(BuildContext context) {
    final query = PerfQuery(
      councilName: widget.councilName,
      sort: _sort,
      ascending: _ascending,
    );
    final perf = ref.watch(councilPerformanceProvider(query));
    return Scaffold(
      appBar: AppBar(
        title: Text('Performance · ${widget.councilName}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                ref.invalidate(councilPerformanceProvider(query)),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                DropdownButton<String>(
                  value: _sort,
                  items: [
                    for (final e in _sortOptions.entries)
                      DropdownMenuItem(
                          value: e.key, child: Text('Sort: ${e.value}'))
                  ],
                  onChanged: (v) => setState(
                      () => _sort = v ?? 'test_pearson_r_mean'),
                ),
                FilterChip(
                  label: const Text('Ascending'),
                  selected: _ascending,
                  onSelected: (v) => setState(() => _ascending = v),
                ),
              ],
            ),
          ),
          Expanded(
            child: perf.when(
              loading: () =>
                  const LoadingView(label: 'Loading performance table…'),
              error: (e, _) => ErrorView(e,
                  onRetry: () =>
                      ref.invalidate(councilPerformanceProvider(query))),
              data: (data) {
                final rows = ((data['rows'] as List?) ?? [])
                    .cast<Map<String, dynamic>>();
                return ResultsTable(
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
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  num? _num(Object? v) => v is num ? v : null;

  String _architecture(Map<String, dynamic> r) {
    final hidden = r['hidden']?.toString() ?? '?';
    final dropout = r['dropout'];
    if (dropout is num) {
      return '$hidden · d=${dropout.toStringAsFixed(2)}';
    }
    return hidden;
  }

  // performance.py serializes feature_ids as a comma-joined string —
  // split here so FeatureChipList can render pastel pills per family.
  List<String> _splitFeatureIds(Object? v) {
    if (v is List) return [for (final f in v) f.toString()];
    if (v is String && v.isNotEmpty) {
      return [for (final f in v.split(',')) if (f.isNotEmpty) f];
    }
    return const [];
  }
}
