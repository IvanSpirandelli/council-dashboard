import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/providers.dart';
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
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted) return;
      ref.invalidate(councilRoundProvider(
          CouncilRoundKey(widget.councilName, widget.roundId)));
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

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
            final nodesPanel = topology.when(
              loading: () => const LoadingView(),
              error: (e, _) => ErrorView(e),
              data: (t) => _NodeList(
                nodes: (t['nodes'] as List).cast<Map<String, dynamic>>(),
                overlay: overlay,
                focusedAgent: _focusedAgent,
                onTap: (id) => setState(
                    () => _focusedAgent = _focusedAgent == id ? null : id),
              ),
            );
            final focusedKind = _focusedKind(topology.value);
            final ioPanel = _IOPanel(
              councilName: widget.councilName,
              roundId: widget.roundId,
              calls: calls,
              focusedAgent: _focusedAgent,
              focusedKind: focusedKind,
              decision: data['decision'] as Map<String, dynamic>?,
              runs: ((data['runs'] as List?) ?? []).cast<Map<String, dynamic>>(),
              summary: data['summary'] as Map<String, dynamic>,
            );
            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 280,
                    child: Card(
                        margin: const EdgeInsets.all(12), child: nodesPanel),
                  ),
                  Expanded(
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
                        margin: const EdgeInsets.all(12), child: nodesPanel)),
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

  String? _focusedKind(Map<String, dynamic>? topo) {
    if (_focusedAgent == null || topo == null) return null;
    final nodes = (topo['nodes'] as List).cast<Map<String, dynamic>>();
    for (final n in nodes) {
      if (n['id'] == _focusedAgent) return n['kind'] as String?;
    }
    return null;
  }
}

/// Vertical column of clickable node tiles, replacing the old graph view.
/// Click toggles focus on a node; the IO panel then filters / switches
/// content (LLM Calls for `llm`, Code for `code`).
class _NodeList extends StatelessWidget {
  const _NodeList({
    required this.nodes,
    required this.overlay,
    required this.focusedAgent,
    required this.onTap,
  });

  final List<Map<String, dynamic>> nodes;
  final Map<String, Map<String, dynamic>> overlay;
  final String? focusedAgent;
  final void Function(String id) onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text('Nodes',
              style: Theme.of(context).textTheme.titleMedium),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Text('Tap to focus. Tap again to clear.',
              style: TextStyle(fontSize: 11)),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: nodes.length,
            separatorBuilder: (_, _) => const SizedBox(height: 2),
            itemBuilder: (ctx, i) {
              final n = nodes[i];
              final id = n['id'] as String;
              final label = (n['label'] as String?) ?? id;
              final kind = (n['kind'] as String?) ?? 'llm';
              final ov = overlay[id];
              return _NodeTile(
                id: id,
                label: label,
                kind: kind,
                overlay: ov,
                selected: id == focusedAgent,
                onTap: () => onTap(id),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _NodeTile extends StatelessWidget {
  const _NodeTile({
    required this.id,
    required this.label,
    required this.kind,
    required this.overlay,
    required this.selected,
    required this.onTap,
  });

  final String id;
  final String label;
  final String kind;
  final Map<String, dynamic>? overlay;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final calls = (overlay?['calls'] as num?) ?? 0;
    final tokens = (overlay?['approx_tokens'] as num?) ?? 0;
    final wall = (overlay?['wall_seconds'] as num?) ?? 0;
    final active = (overlay?['active'] as bool?) ?? false;
    final icon = kind == 'code' ? Icons.code : Icons.smart_toy_outlined;
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? scheme.primaryContainer : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(icon,
                  size: 18,
                  color: active
                      ? Colors.blue
                      : (selected
                          ? scheme.onPrimaryContainer
                          : scheme.onSurfaceVariant)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: Theme.of(context).textTheme.bodyMedium),
                    if (kind == 'llm' && calls > 0)
                      Text(
                        '${calls.toInt()} calls · ≈${_kfmt(tokens)} tok · ${wall.toStringAsFixed(0)}s',
                        style: Theme.of(context).textTheme.bodySmall,
                      )
                    else if (kind == 'llm')
                      Text('idle',
                          style: Theme.of(context).textTheme.bodySmall)
                    else
                      Text('code',
                          style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              if (active)
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _kfmt(num v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).round()}k';
    return v.toString();
  }
}

class _IOPanel extends ConsumerWidget {
  const _IOPanel({
    required this.councilName,
    required this.roundId,
    required this.calls,
    required this.focusedAgent,
    required this.focusedKind,
    required this.decision,
    required this.runs,
    required this.summary,
  });

  final String councilName;
  final String roundId;
  final List<Map<String, dynamic>> calls;
  final String? focusedAgent;
  final String? focusedKind;
  final Map<String, dynamic>? decision;
  final List<Map<String, dynamic>> runs;
  final Map<String, dynamic> summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // When a code node is focused, swap the LLM Calls tab for a Code tab
    // backed by ml-trainer source. Other tabs are council-wide and stay.
    final showCode = focusedAgent != null && focusedKind == 'code';
    final filteredCalls = focusedAgent == null
        ? calls
        : calls.where((c) => c['agent'] == focusedAgent).toList();
    final firstTab = showCode
        ? Tab(text: 'Code · $focusedAgent')
        : Tab(text: focusedAgent == null
            ? 'LLM calls'
            : 'LLM calls · $focusedAgent');
    return DefaultTabController(
      length: 4,
      child: Column(
        children: [
          TabBar(tabs: [
            firstTab,
            const Tab(text: 'Candidates'),
            const Tab(text: 'Results'),
            const Tab(text: 'Raw decision'),
          ]),
          Expanded(
            child: TabBarView(children: [
              showCode
                  ? _CodeTab(
                      councilName: councilName, nodeId: focusedAgent!)
                  : _LLMCallsTab(
                      councilName: councilName,
                      roundId: roundId,
                      calls: filteredCalls,
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
    if (widget.calls.isEmpty) {
      return const Center(
          child: Text('No LLM calls for the selected node yet.'));
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 280,
          child: ListView.separated(
            itemCount: widget.calls.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
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

class _CodeTab extends ConsumerWidget {
  const _CodeTab({required this.councilName, required this.nodeId});
  final String councilName;
  final String nodeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final src = ref.watch(
        councilNodeSourceProvider(CouncilNodeKey(councilName, nodeId)));
    return src.when(
      loading: () => const LoadingView(label: 'Loading source…'),
      error: (e, _) => ErrorView(e),
      data: (data) {
        final sources = ((data['sources'] as List?) ?? [])
            .cast<Map<String, dynamic>>();
        if (sources.isEmpty) {
          return const Center(
              child: Text('No code mapped for this node yet.'));
        }
        return DefaultTabController(
          length: sources.length,
          child: Column(
            children: [
              TabBar(
                isScrollable: true,
                tabs: [for (final s in sources) Tab(text: s['label'] as String)],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    for (final s in sources) _MonoText(s['body'] as String),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
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
