import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/providers.dart';
import '../widgets/error_view.dart';

class PerformancePage extends ConsumerStatefulWidget {
  const PerformancePage({super.key, this.sessionFilter});

  final String? sessionFilter;

  @override
  ConsumerState<PerformancePage> createState() => _PerformancePageState();
}

class _PerformancePageState extends ConsumerState<PerformancePage> {
  String _sort = 'cl2';
  bool _asc = false;
  bool _allVariants = false;

  @override
  Widget build(BuildContext context) {
    final query = PerfQuery(
      session: widget.sessionFilter,
      sort: _sort,
      asc: _asc,
      allVariants: _allVariants,
    );
    final perf = ref.watch(performanceProvider(query));
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.sessionFilter == null
            ? 'Model performance — all sessions'
            : 'Performance · ${widget.sessionFilter}'),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => ref.invalidate(performanceProvider(query))),
        ],
      ),
      body: Column(
        children: [
          _Controls(
            sort: _sort,
            asc: _asc,
            allVariants: _allVariants,
            onChange: (sort, asc, allVariants) =>
                setState(() {
                  _sort = sort;
                  _asc = asc;
                  _allVariants = allVariants;
                }),
          ),
          Expanded(
            child: perf.when(
              loading: () => const LoadingView(label: 'Computing table…'),
              error: (e, _) => ErrorView(e,
                  onRetry: () => ref.invalidate(performanceProvider(query))),
              data: (data) => _Table(data: data),
            ),
          ),
        ],
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.sort,
    required this.asc,
    required this.allVariants,
    required this.onChange,
  });
  final String sort;
  final bool asc;
  final bool allVariants;
  final void Function(String sort, bool asc, bool allVariants) onChange;

  static const _options = [
    'cl2',
    'cl1train',
    'cl1val',
    'bdb',
    'egfr',
    'mpro',
    'fp',
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          DropdownButton<String>(
            value: sort,
            items: [
              for (final o in _options)
                DropdownMenuItem(value: o, child: Text('Sort: $o'))
            ],
            onChanged: (v) => onChange(v ?? 'cl2', asc, allVariants),
          ),
          FilterChip(
            label: const Text('Ascending'),
            selected: asc,
            onSelected: (v) => onChange(sort, v, allVariants),
          ),
          FilterChip(
            label: const Text('All surface variants'),
            selected: allVariants,
            onSelected: (v) => onChange(sort, asc, v),
          ),
        ],
      ),
    );
  }
}

class _Table extends StatelessWidget {
  const _Table({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final rows = ((data['rows'] as List?) ?? []).cast<Map<String, dynamic>>();
    final metrics =
        ((data['metrics'] as List?) ?? []).cast<Map<String, dynamic>>();
    if (rows.isEmpty) {
      return const Center(child: Text('No rows.'));
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          columns: [
            const DataColumn(label: Text('#')),
            const DataColumn(label: Text('fingerprint')),
            const DataColumn(label: Text('round')),
            const DataColumn(label: Text('seeds')),
            for (final m in metrics) DataColumn(label: Text(m['label'] as String)),
            const DataColumn(label: Text('hidden')),
            const DataColumn(label: Text('lr')),
            const DataColumn(label: Text('drop')),
            const DataColumn(label: Text('features')),
          ],
          rows: [
            for (var i = 0; i < rows.length; i++)
              DataRow(cells: [
                DataCell(Text('${i + 1}')),
                DataCell(SelectableText(rows[i]['fingerprint']?.toString() ?? '')),
                DataCell(Text(rows[i]['round']?.toString() ?? '—')),
                DataCell(Text(rows[i]['seeds']?.toString() ?? '—')),
                for (final m in metrics)
                  DataCell(_metricCell(rows[i]['${m['key']}_mean'])),
                DataCell(Text(rows[i]['hidden']?.toString() ?? '—')),
                DataCell(Text(rows[i]['lr']?.toString() ?? '—')),
                DataCell(Text(rows[i]['dropout']?.toString() ?? '—')),
                DataCell(Text(((rows[i]['features'] as List?) ?? []).join(', '))),
              ]),
          ],
        ),
      ),
    );
  }

  Widget _metricCell(Object? v) {
    if (v is num) return Text(v.toStringAsFixed(4));
    return const Text('—');
  }
}
