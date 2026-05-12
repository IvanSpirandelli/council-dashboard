import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/providers.dart';
import '../widgets/error_view.dart';

/// Edits a council's manifest: pick an agent, reorder/toggle/edit its
/// context blocks, watch the live-rendered prompt update, save back.
class CouncilBuilderPage extends ConsumerStatefulWidget {
  const CouncilBuilderPage({
    super.key,
    required this.councilName,
    this.initialAgentId,
  });

  final String councilName;
  final String? initialAgentId;

  @override
  ConsumerState<CouncilBuilderPage> createState() =>
      _CouncilBuilderPageState();
}

class _CouncilBuilderPageState extends ConsumerState<CouncilBuilderPage> {
  Map<String, dynamic>? _manifest;
  String? _agentId;
  bool _dirty = false;
  bool _saving = false;
  String? _error;

  // Preview state.
  String _previewSystem = '';
  String _previewUser = '';
  bool _previewing = false;
  String? _previewError;
  String _extraContext = '';
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadCouncil();
  }

  Future<void> _loadCouncil() async {
    try {
      final api = ref.read(dashboardApiProvider);
      final res = await api.council(widget.councilName);
      // Deep copy via JSON is overkill — manifest dict is mutable enough
      // for our edits; we re-encode on save.
      final manifest = (res['manifest'] as Map).cast<String, dynamic>();
      setState(() {
        _manifest = manifest;
        _agentId = widget.initialAgentId ?? _firstAgentId(manifest);
        _dirty = false;
      });
      await _refreshPreview();
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  String? _firstAgentId(Map<String, dynamic> m) {
    final agents = (m['agents'] as List?) ?? const [];
    if (agents.isEmpty) return null;
    return (agents.first as Map)['id'] as String?;
  }

  Map<String, dynamic>? _agentBlock() {
    if (_manifest == null || _agentId == null) return null;
    final agents = (_manifest!['agents'] as List).cast<Map>();
    for (final a in agents) {
      if (a['id'] == _agentId) return a.cast<String, dynamic>();
    }
    return null;
  }

  List<Map<String, dynamic>> _contextBlocks() {
    final agent = _agentBlock();
    if (agent == null) return [];
    final ctx = (agent['context'] as List?) ?? const [];
    return ctx.cast<Map>().map((m) => m.cast<String, dynamic>()).toList();
  }

  void _setContextBlocks(List<Map<String, dynamic>> blocks) {
    final agent = _agentBlock();
    if (agent == null) return;
    setState(() {
      agent['context'] = blocks;
      _dirty = true;
    });
    _schedulePreview();
  }

  /// Debounce preview-from-body calls so each keystroke doesn't spawn one.
  void _schedulePreview() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _refreshPreview);
  }

  Future<void> _refreshPreview() async {
    if (_agentId == null || _manifest == null) return;
    setState(() {
      _previewing = true;
      _previewError = null;
    });
    try {
      final api = ref.read(dashboardApiProvider);
      final res = await api.councilPreviewFromBody(
        widget.councilName,
        _agentId!,
        _manifest!,
        extraContext: _extraContext.isEmpty ? null : _extraContext,
      );
      setState(() {
        _previewSystem = (res['system_prompt'] as String?) ?? '';
        _previewUser = (res['user_prompt'] as String?) ?? '';
      });
    } catch (e) {
      setState(() => _previewError = e.toString());
    } finally {
      setState(() => _previewing = false);
    }
  }

  Future<void> _save() async {
    if (_manifest == null) return;
    setState(() => _saving = true);
    try {
      final api = ref.read(dashboardApiProvider);
      await api.putCouncil(widget.councilName, _manifest!);
      setState(() => _dirty = false);
      await _refreshPreview();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Manifest saved.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e')),
        );
      }
    } finally {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: Text('Edit ${widget.councilName}')),
        body: ErrorView(_error!),
      );
    }
    if (_manifest == null) {
      return Scaffold(
        appBar: AppBar(title: Text('Edit ${widget.councilName}')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final agentIds = ((_manifest!['agents'] as List?) ?? const [])
        .cast<Map>()
        .map((a) => a['id'] as String)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text('${_manifest!['name']} · $_agentId'),
        actions: [
          if (_dirty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Center(child: Text('● unsaved')),
            ),
          IconButton(
            tooltip: 'Refresh preview',
            icon: const Icon(Icons.refresh),
            onPressed: _previewing ? null : _refreshPreview,
          ),
          IconButton(
            tooltip: 'Save manifest',
            icon: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save_outlined),
            onPressed: _saving || !_dirty ? null : _save,
          ),
        ],
      ),
      body: Column(
        children: [
          _AgentBar(
            agentIds: agentIds,
            current: _agentId!,
            onChanged: (id) async {
              setState(() => _agentId = id);
              await _refreshPreview();
            },
          ),
          const Divider(height: 1),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 460,
                  child: _ContextEditor(
                    blocks: _contextBlocks(),
                    onChanged: _setContextBlocks,
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: _PreviewPane(
                    extraContext: _extraContext,
                    onExtraContextChanged: (v) {
                      setState(() => _extraContext = v);
                    },
                    onRefresh: _refreshPreview,
                    refreshing: _previewing,
                    systemPrompt: _previewSystem,
                    userPrompt: _previewUser,
                    error: _previewError,
                    dirtyHint: _dirty,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


class _AgentBar extends StatelessWidget {
  const _AgentBar({
    required this.agentIds,
    required this.current,
    required this.onChanged,
  });

  final List<String> agentIds;
  final String current;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          const Text('Agent:'),
          const SizedBox(width: 8),
          DropdownButton<String>(
            value: current,
            items: agentIds
                .map((id) => DropdownMenuItem(value: id, child: Text(id)))
                .toList(),
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ],
      ),
    );
  }
}


// ─── Context block editor ────────────────────────────────────────────

class _ContextEditor extends StatelessWidget {
  const _ContextEditor({required this.blocks, required this.onChanged});

  final List<Map<String, dynamic>> blocks;
  final ValueChanged<List<Map<String, dynamic>>> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Context blocks (drag to reorder)',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                tooltip: 'Add block',
                icon: const Icon(Icons.add),
                onPressed: () => _addBlock(context),
              ),
            ],
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
            itemCount: blocks.length,
            buildDefaultDragHandles: false,
            onReorder: (oldI, newI) {
              final next = List<Map<String, dynamic>>.from(blocks);
              if (newI > oldI) newI -= 1;
              final item = next.removeAt(oldI);
              next.insert(newI, item);
              onChanged(next);
            },
            itemBuilder: (context, i) {
              final b = blocks[i];
              return _BlockTile(
                key: ValueKey('block-$i-${b['kind']}-${b['ref'] ?? ''}'),
                index: i,
                block: b,
                onChange: (updated) {
                  final next = List<Map<String, dynamic>>.from(blocks);
                  next[i] = updated;
                  onChanged(next);
                },
                onDelete: () {
                  final next = List<Map<String, dynamic>>.from(blocks);
                  next.removeAt(i);
                  onChanged(next);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  void _addBlock(BuildContext context) async {
    final kind = await showDialog<String>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Add block'),
        children: [
          for (final k in const [
            'resource',
            'history',
            'extra_context',
            'task',
            'raw',
          ])
            SimpleDialogOption(
              child: Text(k),
              onPressed: () => Navigator.pop(context, k),
            ),
        ],
      ),
    );
    if (kind == null) return;
    final next = List<Map<String, dynamic>>.from(blocks);
    next.add({
      'kind': kind,
      if (kind == 'resource') 'ref': '',
      if (kind == 'task' || kind == 'raw') 'text': '',
    });
    onChanged(next);
  }
}


class _BlockTile extends StatelessWidget {
  const _BlockTile({
    super.key,
    required this.index,
    required this.block,
    required this.onChange,
    required this.onDelete,
  });

  final int index;
  final Map<String, dynamic> block;
  final ValueChanged<Map<String, dynamic>> onChange;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final kind = block['kind'] as String? ?? '?';
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                ReorderableDragStartListener(
                  index: index,
                  child: const Padding(
                    padding: EdgeInsets.all(4.0),
                    child: Icon(Icons.drag_indicator, size: 18),
                  ),
                ),
                Chip(
                  label: Text(kind),
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 8),
                if (block['ref'] != null)
                  Expanded(
                    child: Text(
                      block['ref'] as String,
                      style: const TextStyle(fontFamily: 'monospace'),
                      overflow: TextOverflow.ellipsis,
                    ),
                  )
                else
                  const Spacer(),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: onDelete,
                ),
              ],
            ),
            _BlockBody(block: block, onChange: onChange),
          ],
        ),
      ),
    );
  }
}


class _BlockBody extends StatelessWidget {
  const _BlockBody({required this.block, required this.onChange});

  final Map<String, dynamic> block;
  final ValueChanged<Map<String, dynamic>> onChange;

  @override
  Widget build(BuildContext context) {
    final kind = block['kind'] as String? ?? '';
    final children = <Widget>[];

    children.add(_LabeledField(
      label: 'header (optional)',
      value: (block['header'] as String?) ?? '',
      onChange: (v) {
        final next = Map<String, dynamic>.from(block);
        if (v.isEmpty) {
          next.remove('header');
        } else {
          next['header'] = v;
        }
        onChange(next);
      },
    ));

    if (kind == 'resource') {
      children.add(_LabeledField(
        label: 'ref (bundle attr, e.g. wisdom_specific)',
        value: (block['ref'] as String?) ?? '',
        onChange: (v) {
          final next = Map<String, dynamic>.from(block);
          next['ref'] = v;
          onChange(next);
        },
      ));
    } else if (kind == 'history') {
      children.add(_LabeledField(
        label: 'window (optional, defaults to agent.history_window)',
        value: (block['window']?.toString() ?? ''),
        onChange: (v) {
          final next = Map<String, dynamic>.from(block);
          if (v.isEmpty) {
            next.remove('window');
          } else {
            final n = int.tryParse(v);
            if (n != null) next['window'] = n;
          }
          onChange(next);
        },
      ));
    } else if (kind == 'task' || kind == 'raw') {
      children.add(_LabeledField(
        label: 'text (supports {{n_candidates}}, {{history_window}}, ...)',
        value: (block['text'] as String?) ?? '',
        maxLines: 4,
        onChange: (v) {
          final next = Map<String, dynamic>.from(block);
          next['text'] = v;
          onChange(next);
        },
      ));
    }
    // extra_context: header-only — already covered.

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}


class _LabeledField extends StatefulWidget {
  const _LabeledField({
    required this.label,
    required this.value,
    required this.onChange,
    this.maxLines = 1,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChange;
  final int maxLines;

  @override
  State<_LabeledField> createState() => _LabeledFieldState();
}

class _LabeledFieldState extends State<_LabeledField> {
  late final TextEditingController _ctl =
      TextEditingController(text: widget.value);

  @override
  void didUpdateWidget(covariant _LabeledField old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value && widget.value != _ctl.text) {
      _ctl.text = widget.value;
    }
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: TextField(
        controller: _ctl,
        maxLines: widget.maxLines,
        decoration: InputDecoration(
          labelText: widget.label,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        onChanged: widget.onChange,
      ),
    );
  }
}


// ─── Preview pane ────────────────────────────────────────────────────

class _PreviewPane extends StatefulWidget {
  const _PreviewPane({
    required this.extraContext,
    required this.onExtraContextChanged,
    required this.onRefresh,
    required this.refreshing,
    required this.systemPrompt,
    required this.userPrompt,
    required this.error,
    required this.dirtyHint,
  });

  final String extraContext;
  final ValueChanged<String> onExtraContextChanged;
  final VoidCallback onRefresh;
  final bool refreshing;
  final String systemPrompt;
  final String userPrompt;
  final String? error;
  final bool dirtyHint;

  @override
  State<_PreviewPane> createState() => _PreviewPaneState();
}

class _PreviewPaneState extends State<_PreviewPane>
    with SingleTickerProviderStateMixin {
  late final TabController _tab =
      TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'extra_context (optional, fed to extra_context blocks)',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: widget.onExtraContextChanged,
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.play_arrow),
                label: const Text('Render'),
                onPressed: widget.refreshing ? null : widget.onRefresh,
              ),
            ],
          ),
        ),
        TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: 'User prompt'),
            Tab(text: 'System prompt'),
          ],
        ),
        if (widget.refreshing) const LinearProgressIndicator(minHeight: 2),
        if (widget.error != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: ErrorView(widget.error!),
          ),
        Expanded(
          child: TabBarView(
            controller: _tab,
            children: [
              _PromptView(text: widget.userPrompt),
              _PromptView(text: widget.systemPrompt),
            ],
          ),
        ),
      ],
    );
  }
}


class _PromptView extends StatelessWidget {
  const _PromptView({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: SelectableText(
        text.isEmpty ? '(empty — render to populate)' : text,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
      ),
    );
  }
}
