import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/providers.dart';
import '../widgets/agent_graph.dart';
import '../widgets/error_view.dart';

class RoundPage extends ConsumerStatefulWidget {
  const RoundPage({super.key, required this.councilName, required this.roundId});

  final String councilName;
  final String roundId;

  @override
  ConsumerState<RoundPage> createState() => _RoundPageState();
}

class _RoundPageState extends ConsumerState<RoundPage> {
  String? _focusedAgent;

  @override
  Widget build(BuildContext context) {
    final round = ref.watch(councilRoundProvider(
        CouncilRoundKey(widget.councilName, widget.roundId)));
    final topology = ref.watch(councilTopologyProvider(widget.councilName));

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.councilName} · ${widget.roundId}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(councilRoundProvider(
                CouncilRoundKey(widget.councilName, widget.roundId))),
          ),
        ],
      ),
      body: round.when(
        loading: () => const LoadingView(label: 'Loading round…'),
        error: (e, _) => ErrorView(e,
            onRetry: () => ref.invalidate(councilRoundProvider(
                CouncilRoundKey(widget.councilName, widget.roundId)))),
        data: (data) {
          final overlay = ((data['topology_overlay'] as Map?) ?? {})
              .cast<String, Map<String, dynamic>>();
          final calls = ((data['llm_calls'] as List?) ?? [])
              .cast<Map<String, dynamic>>();
          return LayoutBuilder(builder: (ctx, c) {
            final wide = c.maxWidth > 1100;
            final graphPanel = topology.when(
              loading: () => const LoadingView(),
              error: (e, _) => ErrorView(e),
              data: (t) => Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Row(
                      children: [
                        Text('Agent topology',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(width: 12),
                        if (_focusedAgent != null)
                          Chip(
                            label: Text(_focusedAgent!),
                            onDeleted: () =>
                                setState(() => _focusedAgent = null),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: AgentGraph(
                      nodes: (t['nodes'] as List).cast<Map<String, dynamic>>(),
                      edges: (t['edges'] as List).cast<Map<String, dynamic>>(),
                      overlay: overlay,
                      onAgentTap: (id) => setState(() => _focusedAgent = id),
                    ),
                  ),
                ],
              ),
            );
            final ioPanel = _IOPanel(
              councilName: widget.councilName,
              roundId: widget.roundId,
              calls: calls,
              focusedAgent: _focusedAgent,
              decision: data['decision'] as Map<String, dynamic>?,
              runs: ((data['runs'] as List?) ?? []).cast<Map<String, dynamic>>(),
              summary: data['summary'] as Map<String, dynamic>,
            );
            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                      flex: 5,
                      child: Card(
                          margin: const EdgeInsets.all(12), child: graphPanel)),
                  Expanded(
                      flex: 6,
                      child: Card(
                          margin: const EdgeInsets.fromLTRB(0, 12, 12, 12),
                          child: ioPanel)),
                ],
              );
            }
            return ListView(
              children: [
                SizedBox(
                    height: 380,
                    child: Card(
                        margin: const EdgeInsets.all(12), child: graphPanel)),
                Card(
                    margin:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: ioPanel),
              ],
            );
          });
        },
      ),
    );
  }
}

class _IOPanel extends ConsumerWidget {
  const _IOPanel({
    required this.councilName,
    required this.roundId,
    required this.calls,
    required this.focusedAgent,
    required this.decision,
    required this.runs,
    required this.summary,
  });

  final String councilName;
  final String roundId;
  final List<Map<String, dynamic>> calls;
  final String? focusedAgent;
  final Map<String, dynamic>? decision;
  final List<Map<String, dynamic>> runs;
  final Map<String, dynamic> summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filtered = focusedAgent == null
        ? calls
        : calls.where((c) => c['agent_id'] == focusedAgent).toList();
    return DefaultTabController(
      length: 4,
      child: Column(
        children: [
          const TabBar(tabs: [
            Tab(text: 'LLM calls'),
            Tab(text: 'Candidates'),
            Tab(text: 'Results'),
            Tab(text: 'Raw decision'),
          ]),
          Expanded(
            child: TabBarView(children: [
              _LLMCallsTab(
                councilName: councilName,
                roundId: roundId,
                calls: filtered,
              ),
              _CandidatesTab(
                  candidates: ((summary['candidates'] as List?) ?? [])
                      .cast<Map<String, dynamic>>(),
                  rationale: summary['selection_rationale'] as String? ?? ''),
              _ResultsTab(runs: runs),
              _RawDecisionTab(decision: decision),
            ]),
          ),
        ],
      ),
    );
  }
}

class _LLMCallsTab extends ConsumerStatefulWidget {
  const _LLMCallsTab({
    required this.councilName,
    required this.roundId,
    required this.calls,
  });

  final String councilName;
  final String roundId;
  final List<Map<String, dynamic>> calls;

  @override
  ConsumerState<_LLMCallsTab> createState() => _LLMCallsTabState();
}

class _LLMCallsTabState extends ConsumerState<_LLMCallsTab> {
  Map<String, dynamic>? _selected;
  String? _promptBody;
  String? _responseBody;
  Object? _loadError;
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 280,
          child: ListView.separated(
            itemCount: widget.calls.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (ctx, i) {
              final c = widget.calls[i];
              final selected = c == _selected;
              return ListTile(
                dense: true,
                selected: selected,
                title: Text('${c['agent']} t${c['turn']}'),
                subtitle: Text(
                    '${c['model']} · ≈${_kfmt((c['approx_prompt_tokens'] as num) + (c['approx_response_tokens'] as num))} tok · ${(c['wall_seconds'] as num).toStringAsFixed(0)}s'),
                onTap: () => _select(c),
              );
            },
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: _selected == null
              ? const Center(
                  child: Text('Select a call to view its prompt + response.'))
              : _detailView(),
        ),
      ],
    );
  }

  Widget _detailView() {
    if (_loading) return const LoadingView(label: 'Loading…');
    if (_loadError != null) return ErrorView(_loadError!);
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                Text('agent: ${_selected!['agent']}'),
                Text('model: ${_selected!['model']}'),
                Text('turn: ${_selected!['turn']}'),
                Text(
                    '≈ tokens: ${_kfmt((_selected!['approx_prompt_tokens'] as num) + (_selected!['approx_response_tokens'] as num))}'),
                Text('wall: ${(_selected!['wall_seconds'] as num).toStringAsFixed(0)}s'),
                if (_selected!['exact_usage'] != null)
                  Text('exact_usage: ${_selected!['exact_usage']}'),
              ],
            ),
          ),
          const TabBar(tabs: [Tab(text: 'Prompt'), Tab(text: 'Response')]),
          Expanded(
            child: TabBarView(children: [
              _MonoText(_promptBody ?? ''),
              _MonoText(_responseBody ?? ''),
            ]),
          ),
        ],
      ),
    );
  }

  Future<void> _select(Map<String, dynamic> c) async {
    setState(() {
      _selected = c;
      _loading = true;
      _loadError = null;
      _promptBody = null;
      _responseBody = null;
    });
    final api = ref.read(dashboardApiProvider);
    try {
      final promptName = (c['prompt_path'] as String).split('/').last;
      final responseName = (c['response_path'] as String).split('/').last;
      final p = await api.councilLlmArtifact(
          widget.councilName, widget.roundId, promptName);
      final r = await api.councilLlmArtifact(
          widget.councilName, widget.roundId, responseName);
      setState(() {
        _promptBody = p['body'] as String;
        _responseBody = _prettyJson(r['body'] as String);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loadError = e;
        _loading = false;
      });
    }
  }

  String _prettyJson(String s) {
    try {
      return const JsonEncoder.withIndent('  ').convert(jsonDecode(s));
    } catch (_) {
      return s;
    }
  }

  String _kfmt(num v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).round()}k';
    return v.toString();
  }
}

class _MonoText extends StatelessWidget {
  const _MonoText(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: SingleChildScrollView(
        child: SelectableText(
          text,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontFamilyFallback: ['Menlo', 'Courier'],
            fontSize: 12.5,
          ),
        ),
      ),
    );
  }
}

class _CandidatesTab extends StatelessWidget {
  const _CandidatesTab({required this.candidates, required this.rationale});
  final List<Map<String, dynamic>> candidates;
  final String rationale;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (rationale.isNotEmpty)
          Card(
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SelectableText(rationale,
                  style: Theme.of(context).textTheme.bodyMedium),
            ),
          ),
        const SizedBox(height: 8),
        for (final c in candidates) _CandidateCard(c: c),
      ],
    );
  }
}

class _CandidateCard extends StatelessWidget {
  const _CandidateCard({required this.c});
  final Map<String, dynamic> c;

  @override
  Widget build(BuildContext context) {
    final feats = (c['feature_ids'] as List?)?.cast<String>() ?? const [];
    final flags = (c['risk_flags'] as List?)?.cast<String>() ?? const [];
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: c['promoted'] == true
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.outlineVariant,
          width: c['promoted'] == true ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Chip(
                label: Text(c['proposer']?.toString() ?? 'unknown'),
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 8),
              if (c['promoted'] == true)
                Chip(
                  label: const Text('promoted'),
                  backgroundColor:
                      Theme.of(context).colorScheme.primaryContainer,
                ),
              const Spacer(),
              SelectableText('id: ${c['experiment_id']}',
                  style: Theme.of(context).textTheme.bodySmall),
            ]),
            const SizedBox(height: 6),
            Text('model: ${c['model_family']} · hidden: ${c['hidden']}',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 6),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final f in feats)
                  Chip(label: Text(f), visualDensity: VisualDensity.compact)
              ],
            ),
            if (flags.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 4,
                children: [
                  for (final f in flags)
                    Chip(
                      label: Text(f),
                      backgroundColor:
                          Theme.of(context).colorScheme.errorContainer,
                      visualDensity: VisualDensity.compact,
                    )
                ],
              ),
            ],
            if ((c['rationale_excerpt'] as String?)?.isNotEmpty == true) ...[
              const SizedBox(height: 8),
              SelectableText(c['rationale_excerpt'] as String,
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}

class _ResultsTab extends StatelessWidget {
  const _ResultsTab({required this.runs});
  final List<Map<String, dynamic>> runs;

  @override
  Widget build(BuildContext context) {
    if (runs.isEmpty) {
      return const Center(child: Text('No executed runs in this round.'));
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          columns: const [
            DataColumn(label: Text('experiment_id')),
            DataColumn(label: Text('fingerprint')),
            DataColumn(label: Text('seeds')),
            DataColumn(label: Text('CL2 r')),
            DataColumn(label: Text('val r')),
            DataColumn(label: Text('BDB r')),
            DataColumn(label: Text('EGFR r')),
            DataColumn(label: Text('MPro r')),
          ],
          rows: [
            for (final r in runs)
              DataRow(cells: [
                DataCell(Text(r['experiment_id']?.toString() ?? '—')),
                DataCell(SelectableText(r['fingerprint']?.toString() ?? '—')),
                DataCell(Text(
                    '${(r['n_seeds_succeeded'] ?? '?')}/${(r['n_seeds_total'] ?? '?')}')),
                DataCell(_metricCell(r['test_pearson_r_mean'])),
                DataCell(_metricCell(r['val_pearson_r_mean'])),
                DataCell(_metricCell(r['bdb2020_pearson_r_mean'])),
                DataCell(_metricCell(r['egfr_pearson_r_mean'])),
                DataCell(_metricCell(r['mpro_pearson_r_mean'])),
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

class _RawDecisionTab extends StatelessWidget {
  const _RawDecisionTab({required this.decision});
  final Map<String, dynamic>? decision;

  @override
  Widget build(BuildContext context) {
    if (decision == null) {
      return const Center(child: Text('No decision.json found.'));
    }
    final pretty = const JsonEncoder.withIndent('  ').convert(decision);
    return _MonoText(pretty);
  }
}
