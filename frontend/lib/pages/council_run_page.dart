import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/providers.dart';
import '../widgets/agent_graph.dart';
import '../widgets/error_view.dart';
import '../widgets/launch_config_panel.dart';
import '../widgets/one_round_command_panel.dart';

/// Detailed view of a council's canonical session: rounds, topology
/// overlay, start/stop controls.
///
/// Auto-polls the session endpoint every 2s while mounted; the endpoint
/// is cheap (file reads + a `kill -0` liveness check) so the load is
/// trivial. Manual refresh stays as a fallback in the app bar.
class CouncilRunPage extends ConsumerStatefulWidget {
  const CouncilRunPage({super.key, required this.councilName});

  final String councilName;

  @override
  ConsumerState<CouncilRunPage> createState() => _CouncilRunPageState();
}

class _CouncilRunPageState extends ConsumerState<CouncilRunPage> {
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
    final session = ref.watch(councilSessionProvider(widget.councilName));
    final topology = ref.watch(councilTopologyProvider(widget.councilName));
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.councilName} · run'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                ref.invalidate(councilSessionProvider(widget.councilName)),
          ),
        ],
      ),
      body: session.when(
        loading: () => const LoadingView(label: 'Loading session…'),
        error: (e, _) => ErrorView(e,
            onRetry: () =>
                ref.invalidate(councilSessionProvider(widget.councilName))),
        data: (data) => _Body(
          councilName: widget.councilName,
          summary: data,
          topology: topology,
          onStop: () async {
            final api = ref.read(dashboardApiProvider);
            try {
              await api.councilStop(widget.councilName);
              ref.invalidate(councilSessionProvider(widget.councilName));
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
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.councilName,
    required this.summary,
    required this.topology,
    required this.onStop,
  });

  final String councilName;
  final Map<String, dynamic> summary;
  final AsyncValue<Map<String, dynamic>> topology;
  final Future<void> Function() onStop;

  @override
  Widget build(BuildContext context) {
    final rounds = (summary['rounds'] as List).cast<Map<String, dynamic>>();
    final overlay = ((summary['topology_overlay'] as Map?) ?? {})
        .cast<String, Map<String, dynamic>>();
    final runner = summary['runner'] as Map<String, dynamic>?;
    final running = (runner?['alive'] ?? false) as bool;
    final stopPending = summary['stop_pending'] == true;
    final currentRoundId = summary['current_round_id'] as String?;
    final knownIds = rounds.map((r) => r['round_id'] as String).toSet();
    // Newest first: the in-flight pending round (if any) sits at the very
    // top, followed by completed rounds in reverse-chronological order.
    final displayRounds = <Map<String, dynamic>>[
      if (running &&
          currentRoundId != null &&
          !knownIds.contains(currentRoundId))
        {
          'round_id': currentRoundId,
          'status': 'pending',
          'promoted_count': 0,
          'candidate_count': 0,
          'executed_count': 0,
          'llm_call_count': 0,
          'approx_tokens': 0,
        },
      ...rounds.reversed,
    ];

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
                _stat('≈ Tokens',
                    _kfmt(summary['approx_tokens_total'] as num? ?? 0)),
                const Divider(),
                ListTile(
                  leading:
                      Icon(running ? Icons.play_circle : Icons.stop_circle),
                  title: Text(running ? 'Running' : 'Idle'),
                  subtitle: Text(stopPending
                      ? 'Stop pending — exits after current round'
                      : (runner == null
                          ? 'No runner state'
                          : (runner['status']?.toString() ?? '—'))),
                ),
                if (running)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.tonalIcon(
                        onPressed: () => onStop(),
                        icon: const Icon(Icons.stop),
                        label: const Text('Stop'),
                      ),
                    ),
                  ),
                LaunchConfigPanel(
                  councilName: councilName,
                  running: running,
                ),
                const Divider(),
                OneRoundCommandPanel(councilName: councilName),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text('Rounds',
                      style: Theme.of(context).textTheme.titleSmall),
                ),
                if (displayRounds.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No rounds yet — Save & Start to begin.'),
                  ),
                for (final r in displayRounds) _roundTile(context, r),
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
                        'Agent topology — overlay aggregates this council',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ),
                  Expanded(
                    child: AgentGraph(
                      nodes:
                          (t['nodes'] as List).cast<Map<String, dynamic>>(),
                      edges:
                          (t['edges'] as List).cast<Map<String, dynamic>>(),
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

  Widget _roundTile(BuildContext context, Map<String, dynamic> r) {
    final status = (r['status'] as String?) ?? 'completed';
    final id = r['round_id'] as String;
    final shortId = id.replaceAll('round_', '');
    final isPending = status == 'pending';
    final isRunning = status == 'running';
    final trailing = isPending || isRunning
        ? Chip(
            label: Text(isPending ? 'pending' : 'running'),
            visualDensity: VisualDensity.compact,
            backgroundColor: isRunning
                ? Colors.blue.withValues(alpha: 0.15)
                : Colors.grey.withValues(alpha: 0.15),
          )
        : (r['stop_signal'] != null
            ? Chip(
                label: Text(r['stop_signal'] as String),
                visualDensity: VisualDensity.compact,
              )
            : null);
    final title = isPending
        ? Text('Round $shortId — pending')
        : Text(
            '${r['promoted_count']} promoted / ${r['candidate_count']} cands · ${r['executed_count']} runs');
    final subtitle = isPending
        ? const Text('waiting for first LLM call…')
        : Text(
            '${r['llm_call_count']} LLM calls · ≈${_kfmt(r['approx_tokens'] as num? ?? 0)} tok');
    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 14,
        backgroundColor: isRunning
            ? Colors.blue
            : (isPending ? Colors.grey : null),
        child: Text(shortId, style: const TextStyle(fontSize: 11)),
      ),
      title: title,
      subtitle: subtitle,
      trailing: trailing,
      onTap: isPending
          ? null
          : () => context.push('/councils/$councilName/rounds/$id'),
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
    if (v >= 1000) return '${(v / 1000).round()}k';
    return v.toString();
  }
}
