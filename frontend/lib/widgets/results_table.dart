import 'package:flutter/material.dart';

import 'feature_chip.dart';

/// Normalized row for [ResultsTable]. The three call sites (round results,
/// top performers, full performance table) feed differently shaped JSON;
/// each page is responsible for projecting its rows into this shape.
class ResultRow {
  const ResultRow({
    required this.id,
    this.cl2,
    this.bdb,
    this.egfr,
    this.mpro,
    this.featureIds = const [],
    this.architecture = '—',
  });
  final String id;
  final num? cl2;
  final num? bdb;
  final num? egfr;
  final num? mpro;
  final List<String> featureIds;
  final String architecture;
}

/// Shared results table. Layout matches the round-page Results tab:
/// ID · CL2 · BDB · EGFR · MPro · features · architecture.
class ResultsTable extends StatelessWidget {
  const ResultsTable({
    super.key,
    required this.rows,
    this.idLabel = 'id',
    this.featureMaxWidth = 420,
    this.emptyMessage = 'No rows.',
  });

  final List<ResultRow> rows;
  final String idLabel;
  final double featureMaxWidth;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Center(child: Text(emptyMessage));
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          columnSpacing: 16,
          columns: [
            DataColumn(label: Text(idLabel)),
            const DataColumn(label: Text('CL2 r')),
            const DataColumn(label: Text('BDB r')),
            const DataColumn(label: Text('EGFR r')),
            const DataColumn(label: Text('MPro r')),
            const DataColumn(label: Text('features')),
            const DataColumn(label: Text('architecture')),
          ],
          rows: [
            for (final r in rows)
              DataRow(cells: [
                DataCell(SelectableText(r.id)),
                DataCell(_metric(r.cl2)),
                DataCell(_metric(r.bdb)),
                DataCell(_metric(r.egfr)),
                DataCell(_metric(r.mpro)),
                DataCell(FeatureChipList(
                  featureIds: r.featureIds,
                  maxWidth: featureMaxWidth,
                )),
                DataCell(Text(r.architecture)),
              ]),
          ],
        ),
      ),
    );
  }

  Widget _metric(num? v) {
    if (v == null) return const Text('—');
    return Text(v.toStringAsFixed(4));
  }
}
