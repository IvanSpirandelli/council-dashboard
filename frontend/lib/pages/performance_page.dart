import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/providers.dart';
import '../widgets/error_view.dart';
import '../widgets/feature_chip.dart';

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
    'val_pearson_r_mean': 'val r',
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
                if (rows.isEmpty) {
                  return const Center(child: Text('No models in corpus.'));
                }
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SingleChildScrollView(
                    child: DataTable(
                      columnSpacing: 16,
                      columns: const [
                        DataColumn(label: Text('#')),
                        DataColumn(label: Text('fingerprint')),
                        DataColumn(label: Text('seeds')),
                        DataColumn(label: Text('CL2 r')),
                        DataColumn(label: Text('val r')),
                        DataColumn(label: Text('BDB r')),
                        DataColumn(label: Text('EGFR r')),
                        DataColumn(label: Text('MPro r')),
                        DataColumn(label: Text('hidden')),
                        DataColumn(label: Text('lr')),
                        DataColumn(label: Text('drop')),
                        DataColumn(label: Text('features')),
                      ],
                      rows: [
                        for (var i = 0; i < rows.length; i++)
                          DataRow(cells: [
                            DataCell(Text('${i + 1}')),
                            DataCell(SelectableText(
                                rows[i]['fingerprint']?.toString() ?? '')),
                            DataCell(Text(
                                '${rows[i]['n_seeds_succeeded'] ?? '?'}/${rows[i]['n_seeds'] ?? '?'}')),
                            DataCell(_metric(rows[i]['test_pearson_r_mean'])),
                            DataCell(_metric(rows[i]['val_pearson_r_mean'])),
                            DataCell(
                                _metric(rows[i]['bdb2020_pearson_r_mean'])),
                            DataCell(_metric(rows[i]['egfr_pearson_r_mean'])),
                            DataCell(_metric(rows[i]['mpro_pearson_r_mean'])),
                            DataCell(
                                Text(rows[i]['hidden']?.toString() ?? '—')),
                            DataCell(Text(rows[i]['lr']?.toString() ?? '—')),
                            DataCell(
                                Text(rows[i]['dropout']?.toString() ?? '—')),
                            DataCell(FeatureChipList(
                              featureIds: _splitFeatureIds(
                                  rows[i]['feature_ids']),
                              maxWidth: 320,
                            )),
                          ]),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _metric(Object? v) {
    if (v is num) return Text(v.toStringAsFixed(4));
    return const Text('—');
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
