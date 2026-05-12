import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/providers.dart';
import '../widgets/error_view.dart';
import '../widgets/feature_chip.dart';

/// Per-council home: performance preview, edit-council, continue-tasks.
///
/// Auto-polls the session endpoint every 2s while mounted so the
/// Running/Idle badge stays current; the perf provider is only
/// refreshed on manual button press (it sorts the whole model corpus
/// and is comparatively expensive).
class CouncilHomePage extends ConsumerStatefulWidget {
  const CouncilHomePage({super.key, required this.councilName});

  final String councilName;

  @override
  ConsumerState<CouncilHomePage> createState() => _CouncilHomePageState();
}

class _CouncilHomePageState extends ConsumerState<CouncilHomePage> {
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted) return;
      ref.invalidate(councilSessionProvider(widget.councilName));
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final perf = ref.watch(councilPerformanceProvider(
      PerfQuery(councilName: widget.councilName, limit: 10),
    ));
    final session = ref.watch(councilSessionProvider(widget.councilName));
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.councilName),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(councilPerformanceProvider(
                PerfQuery(councilName: widget.councilName, limit: 10),
              ));
              ref.invalidate(councilSessionProvider(widget.councilName));
            },
          ),
        ],
      ),
      body: LayoutBuilder(builder: (ctx, c) {
        final wide = c.maxWidth > 900;
        final perfTile = _PerformanceTile(
          councilName: widget.councilName,
          perf: perf,
        );
        final actionTiles = _ActionTiles(
          councilName: widget.councilName,
          session: session,
        );
        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 3, child: perfTile),
              Expanded(flex: 2, child: actionTiles),
            ],
          );
        }
        return ListView(
          children: [
            SizedBox(height: 420, child: perfTile),
            actionTiles,
          ],
        );
      }),
    );
  }
}

class _PerformanceTile extends StatelessWidget {
  const _PerformanceTile({required this.councilName, required this.perf});
  final String councilName;
  final AsyncValue<Map<String, dynamic>> perf;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            title: Text('Top performers',
                style: Theme.of(context).textTheme.titleMedium),
            subtitle: perf.maybeWhen(
              data: (d) => Text('${d['n_total']} models in corpus'),
              orElse: () => const Text(''),
            ),
            trailing: TextButton.icon(
              icon: const Icon(Icons.open_in_new),
              label: const Text('Full table'),
              onPressed: () =>
                  context.push('/councils/$councilName/performance'),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: perf.when(
              loading: () => const LoadingView(label: 'Loading…'),
              error: (e, _) => ErrorView(e),
              data: (d) {
                final rows =
                    ((d['rows'] as List?) ?? []).cast<Map<String, dynamic>>();
                if (rows.isEmpty) {
                  return const Center(
                      child: Text('No models in corpus yet.'));
                }
                return _PerfRows(rows: rows);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PerfRows extends StatelessWidget {
  const _PerfRows({required this.rows});
  final List<Map<String, dynamic>> rows;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 16,
        columns: const [
          DataColumn(label: Text('#')),
          DataColumn(label: Text('fingerprint')),
          DataColumn(label: Text('CL2 r')),
          DataColumn(label: Text('BDB r')),
          DataColumn(label: Text('EGFR r')),
          DataColumn(label: Text('MPro r')),
          DataColumn(label: Text('features')),
          DataColumn(label: Text('architecture')),
        ],
        rows: [
          for (var i = 0; i < rows.length; i++)
            DataRow(cells: [
              DataCell(Text('${i + 1}')),
              DataCell(SelectableText(
                  rows[i]['fingerprint']?.toString() ?? '')),
              DataCell(_metric(rows[i]['test_pearson_r_mean'])),
              DataCell(_metric(rows[i]['bdb2020_pearson_r_mean'])),
              DataCell(_metric(rows[i]['egfr_pearson_r_mean'])),
              DataCell(_metric(rows[i]['mpro_pearson_r_mean'])),
              DataCell(FeatureChipList(
                featureIds: _splitFeatureIds(rows[i]['feature_ids']),
                maxWidth: 420,
              )),
              DataCell(Text(rows[i]['hidden']?.toString() ?? '—')),
            ]),
        ],
      ),
    );
  }

  Widget _metric(Object? v) {
    if (v is num) return Text(v.toStringAsFixed(4));
    return const Text('—');
  }

  // performance.py serializes feature_ids as a comma-joined string, not
  // a list — split here so FeatureChipList can render pastel pills.
  List<String> _splitFeatureIds(Object? v) {
    if (v is List) return [for (final f in v) f.toString()];
    if (v is String && v.isNotEmpty) {
      return [for (final f in v.split(',')) if (f.isNotEmpty) f];
    }
    return const [];
  }
}

class _ActionTiles extends StatelessWidget {
  const _ActionTiles({required this.councilName, required this.session});
  final String councilName;
  final AsyncValue<Map<String, dynamic>> session;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ActionCard(
            icon: Icons.edit_note,
            title: 'Edit council',
            subtitle:
                'Manifest, prompts, resources, agent topology, preview.',
            onTap: () => context.push('/councils/$councilName/edit'),
          ),
          const SizedBox(height: 12),
          _ContinueTasksCard(councilName: councilName, session: session),
        ],
      ),
    );
  }
}

class _ContinueTasksCard extends StatelessWidget {
  const _ContinueTasksCard({
    required this.councilName,
    required this.session,
  });
  final String councilName;
  final AsyncValue<Map<String, dynamic>> session;

  @override
  Widget build(BuildContext context) {
    return session.when(
      loading: () => const _ActionCard(
        icon: Icons.hourglass_top,
        title: 'Continue tasks',
        subtitle: 'Loading session state…',
      ),
      error: (e, _) => _ActionCard(
        icon: Icons.error_outline,
        title: 'Continue tasks',
        subtitle: 'Backend error: $e',
      ),
      data: (s) {
        final runner = s['runner'] as Map<String, dynamic>?;
        final running = (runner?['alive'] ?? false) as bool;
        final stopPending = s['stop_pending'] == true;
        final rounds = (s['rounds'] as List?)?.length ?? 0;
        final subtitle = StringBuffer()
          ..write(running ? 'Running' : 'Idle')
          ..write(' · $rounds round${rounds == 1 ? '' : 's'}');
        if (stopPending) subtitle.write(' · stop pending');
        return _ActionCard(
          icon: running ? Icons.play_circle : Icons.play_arrow,
          title: 'Continue tasks',
          subtitle: subtitle.toString(),
          onTap: () => context.push('/councils/$councilName/run'),
        );
      },
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(icon, size: 32),
        title:
            Text(title, style: Theme.of(context).textTheme.titleMedium),
        subtitle: Text(subtitle),
        trailing:
            onTap != null ? const Icon(Icons.chevron_right) : null,
        onTap: onTap,
      ),
    );
  }
}
