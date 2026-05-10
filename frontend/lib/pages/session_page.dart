import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/providers.dart';
import '../widgets/agent_graph.dart';
import '../widgets/error_view.dart';

class SessionPage extends ConsumerWidget {
  const SessionPage({super.key, required this.sessionId});

  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider(sessionId));
    final topology = ref.watch(topologyProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(sessionId),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(sessionProvider(sessionId)),
          ),
          IconButton(
            tooltip: 'Performance table for this session',
            icon: const Icon(Icons.table_chart_outlined),
            onPressed: () => context.push('/performance?session=$sessionId'),
          ),
        ],
      ),
      body: session.when(
        loading: () => const LoadingView(label: 'Loading session…'),
        error: (e, _) => ErrorView(e,
            onRetry: () => ref.invalidate(sessionProvider(sessionId))),
        data: (data) => _SessionBody(
          sessionId: sessionId,
          summary: data,
          topology: topology,
          onStop: () async {
            final api = ref.read(dashboardApiProvider);
            try {
              await api.stop(sessionId);
              ref.invalidate(sessionProvider(sessionId));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text(
                          '.STOP written. Council exits cleanly after current round.')),
                );
              }
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Stop failed: $e')),
                );
              }
            }
          },
          onResume: () async {
            final api = ref.read(dashboardApiProvider);
            try {
              await api.clearStop(sessionId);
              await api.start(sessionId);
              ref.invalidate(sessionProvider(sessionId));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Council launched.')));
              }
            } catch (e) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Start failed: $e')));
              }
            }
          },
        ),
      ),
    );
  }
}

class _SessionBody extends StatelessWidget {
  const _SessionBody({
    required this.sessionId,
    required this.summary,
    required this.topology,
    required this.onStop,
    required this.onResume,
  });

  final String sessionId;
  final Map<String, dynamic> summary;
  final AsyncValue<Map<String, dynamic>> topology;
  final Future<void> Function() onStop;
  final Future<void> Function() onResume;

  @override
  Widget build(BuildContext context) {
    final rounds = (summary['rounds'] as List).cast<Map<String, dynamic>>();
    final overlay = ((summary['topology_overlay'] as Map?) ?? {})
        .cast<String, Map<String, dynamic>>();
    final runner = summary['runner'] as Map<String, dynamic>?;
    final running = (runner?['alive'] ?? false) as bool;
    final stopPending = summary['stop_pending'] == true;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 360,
          child: Card(
            margin: const EdgeInsets.all(12),
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _stat('Rounds', '${summary['rounds']?.length ?? 0}'),
                _stat('Promoted total', '${summary['promoted_total']}'),
                _stat('LLM calls', '${summary['llm_call_total']}'),
                _stat(
                    '≈ Tokens', _kfmt(summary['approx_tokens_total'] as num? ?? 0)),
                const Divider(),
                ListTile(
                  leading: Icon(running ? Icons.play_circle : Icons.stop_circle),
                  title: Text(running ? 'Running' : 'Idle'),
                  subtitle: Text(stopPending
                      ? 'Stop pending — exits after current round'
                      : (runner == null
                          ? 'No runner state'
                          : (runner['status']?.toString() ?? '—'))),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: running ? () => onStop() : null,
                        icon: const Icon(Icons.stop),
                        label: const Text('Stop'),
                      ),
                      FilledButton.icon(
                        onPressed: running ? null : () => onResume(),
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Start / Resume'),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text('Rounds',
                      style: Theme.of(context).textTheme.titleSmall),
                ),
                for (final r in rounds)
                  ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 14,
                      child: Text(
                        '${r['round_id']}'.replaceAll('round_', ''),
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                    title: Text(
                        '${r['promoted_count']} promoted / ${r['candidate_count']} cands · ${r['executed_count']} runs'),
                    subtitle: Text(
                        '${r['llm_call_count']} LLM calls · ≈${_kfmt(r['approx_tokens'] as num? ?? 0)} tok'),
                    trailing: r['stop_signal'] != null
                        ? Chip(
                            label: Text(r['stop_signal'] as String),
                            visualDensity: VisualDensity.compact,
                          )
                        : null,
                    onTap: () => context.push(
                        '/sessions/$sessionId/rounds/${r['round_id']}'),
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: Card(
            margin: const EdgeInsets.fromLTRB(0, 12, 12, 12),
            child: topology.when(
              loading: () => const LoadingView(),
              error: (e, _) => ErrorView(e),
              data: (t) => Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Agent topology — overlay aggregates this session',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ),
                  Expanded(
                    child: AgentGraph(
                      nodes: (t['nodes'] as List).cast<Map<String, dynamic>>(),
                      edges: (t['edges'] as List).cast<Map<String, dynamic>>(),
                      overlay: overlay,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _stat(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      );

  String _kfmt(num v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
    return v.toString();
  }
}
