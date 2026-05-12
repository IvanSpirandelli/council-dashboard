import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/providers.dart';
import '../widgets/error_view.dart';

/// Per-council home: performance preview, edit-council, continue-tasks.
class CouncilHomePage extends ConsumerWidget {
  const CouncilHomePage({super.key, required this.councilName});

  final String councilName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final perf = ref.watch(councilPerformanceProvider(
      PerfQuery(councilName: councilName, limit: 10),
    ));
    final session = ref.watch(councilSessionProvider(councilName));
    return Scaffold(
      appBar: AppBar(
        title: Text(councilName),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(councilPerformanceProvider(
                PerfQuery(councilName: councilName, limit: 10),
              ));
              ref.invalidate(councilSessionProvider(councilName));
            },
          ),
        ],
      ),
      body: LayoutBuilder(builder: (ctx, c) {
        final wide = c.maxWidth > 900;
        final perfTile = _PerformanceTile(
          councilName: councilName,
          perf: perf,
        );
        final actionTiles = _ActionTiles(
          councilName: councilName,
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
          DataColumn(label: Text('val r')),
          DataColumn(label: Text('BDB r')),
          DataColumn(label: Text('hidden')),
          DataColumn(label: Text('features')),
        ],
        rows: [
          for (var i = 0; i < rows.length; i++)
            DataRow(cells: [
              DataCell(Text('${i + 1}')),
              DataCell(SelectableText(
                  rows[i]['fingerprint']?.toString() ?? '')),
              DataCell(_metric(rows[i]['test_pearson_r_mean'])),
              DataCell(_metric(rows[i]['val_pearson_r_mean'])),
              DataCell(_metric(rows[i]['bdb2020_pearson_r_mean'])),
              DataCell(Text(rows[i]['hidden']?.toString() ?? '—')),
              DataCell(SizedBox(
                width: 220,
                child: Text(
                  rows[i]['feature_ids']?.toString() ?? '',
                  overflow: TextOverflow.ellipsis,
                ),
              )),
            ]),
        ],
      ),
    );
  }

  Widget _metric(Object? v) {
    if (v is num) return Text(v.toStringAsFixed(4));
    return const Text('—');
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
