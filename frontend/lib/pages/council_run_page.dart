import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/providers.dart';
import '../widgets/agent_graph.dart';
import '../widgets/error_view.dart';
import '../widgets/input_node_dialog.dart';
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
  final AgentGraphController _graphController = AgentGraphController();

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

  Future<void> _saveLayout() async {
    final positions = _graphController.snapshotNormalized();
    if (positions == null || positions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Graph not laid out yet.')),
      );
      return;
    }
    final api = ref.read(dashboardApiProvider);
    try {
      final council = await api.council(widget.councilName);
      final manifest = Map<String, dynamic>.from(council['manifest'] as Map);
      final topology = Map<String, dynamic>.from(
          (manifest['topology'] as Map?) ?? {});
      final nodes = ((topology['nodes'] as List?) ?? [])
          .map((n) => Map<String, dynamic>.from(n as Map))
          .toList();
      for (final n in nodes) {
        final p = positions[n['id'] as String];
        if (p == null) continue;
        n['x'] = double.parse(p.x.toStringAsFixed(4));
        n['y'] = double.parse(p.y.toStringAsFixed(4));
      }
      topology['nodes'] = nodes;
      manifest['topology'] = topology;
      await api.putCouncil(widget.councilName, manifest);
      ref.invalidate(councilTopologyProvider(widget.councilName));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Graph layout saved.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e')),
        );
      }
    }
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
          graphController: _graphController,
          onSaveLayout: _saveLayout,
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
    required this.graphController,
    required this.onSaveLayout,
    required this.onStop,
  });

  final String councilName;
  final Map<String, dynamic> summary;
  final AsyncValue<Map<String, dynamic>> topology;
  final AgentGraphController graphController;
  final Future<void> Function() onSaveLayout;
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
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Node Interaction Graph',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: onSaveLayout,
                          icon: const Icon(Icons.save_outlined, size: 18),
                          label: const Text('Save layout'),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: AgentGraph(
                      nodes:
                          (t['nodes'] as List).cast<Map<String, dynamic>>(),
                      edges:
                          (t['edges'] as List).cast<Map<String, dynamic>>(),
                      overlay: overlay,
                      controller: graphController,
                      onAgentTap: (id) => _onNodeTap(
                          context,
                          (t['nodes'] as List).cast<Map<String, dynamic>>(),
                          id),
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

  void _onNodeTap(
    BuildContext context,
    List<Map<String, dynamic>> nodes,
    String id,
  ) {
    final node = nodes.firstWhere(
      (n) => n['id'] == id,
      orElse: () => const <String, dynamic>{},
    );
    if (node.isEmpty) return;
    final kind = node['kind'] as String?;
    // Only input nodes get a dialog today; agent/code nodes just toggle
    // the in-graph focus highlight via AgentGraph's internal state.
    const inputKinds = {'file', 'generated', 'human_override'};
    if (!inputKinds.contains(kind)) return;
    showInputNodeDialog(context, councilName: councilName, node: node);
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
