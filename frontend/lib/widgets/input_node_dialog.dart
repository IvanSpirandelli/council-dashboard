import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/providers.dart';

/// Modal opened when an input node (kind: file / generated / human_override)
/// is tapped on the agent graph. Branches on kind: file + human_override
/// give an editor over the resource file; generated reads the producing
/// Python via the existing /nodes/{id}/source endpoint and shows it
/// read-only.
Future<void> showInputNodeDialog(
  BuildContext context, {
  required String councilName,
  required Map<String, dynamic> node,
}) {
  return showDialog(
    context: context,
    builder: (_) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 700),
        child: _InputNodeDialogBody(councilName: councilName, node: node),
      ),
    ),
  );
}

class _InputNodeDialogBody extends ConsumerStatefulWidget {
  const _InputNodeDialogBody({required this.councilName, required this.node});

  final String councilName;
  final Map<String, dynamic> node;

  @override
  ConsumerState<_InputNodeDialogBody> createState() =>
      _InputNodeDialogBodyState();
}

class _InputNodeDialogBodyState extends ConsumerState<_InputNodeDialogBody> {
  final _ctrl = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;
  String _loadedBody = '';
  String? _error;
  // For generated nodes: read-only source body + path label.
  List<Map<String, String>> _sources = const [];

  String get _kind => (widget.node['kind'] as String?) ?? '';
  String get _id => widget.node['id'] as String;
  String get _label => (widget.node['label'] as String?) ?? _id;
  bool get _isGenerated => _kind == 'generated';
  bool get _isEditable => _kind == 'file' || _kind == 'human_override';

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() {
      final next = _ctrl.text != _loadedBody;
      if (next != _dirty) setState(() => _dirty = next);
    });
    _load();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final api = ref.read(dashboardApiProvider);
    try {
      if (_isGenerated) {
        final r = await api.councilNodeSource(widget.councilName, _id);
        final sources = ((r['sources'] as List?) ?? [])
            .cast<Map<String, dynamic>>()
            .map((s) => {
                  'label': (s['label'] as String?) ?? '',
                  'path': (s['path'] as String?) ?? '',
                  'body': (s['body'] as String?) ?? '',
                })
            .toList();
        setState(() {
          _sources = sources;
          _loading = false;
          _error = null;
        });
      } else if (_isEditable) {
        final resourceName = (widget.node['resource'] as String?) ?? '';
        if (resourceName.isEmpty) {
          throw StateError('node $_id has no resource: field on it');
        }
        final r = await api.councilResource(widget.councilName, resourceName);
        final body = (r['body'] as String?) ?? '';
        _loadedBody = body;
        _ctrl.text = body;
        setState(() {
          _loading = false;
          _error = null;
        });
      } else {
        setState(() {
          _loading = false;
          _error = 'no dialog content for node kind "$_kind"';
        });
      }
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _save() async {
    final resourceName = (widget.node['resource'] as String?) ?? '';
    if (resourceName.isEmpty) return;
    setState(() => _saving = true);
    try {
      await ref.read(dashboardApiProvider).putCouncilResource(
            widget.councilName,
            resourceName,
            _ctrl.text,
          );
      _loadedBody = _ctrl.text;
      if (mounted) {
        setState(() {
          _saving = false;
          _dirty = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved $resourceName')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: Row(
            children: [
              Icon(_iconForKind(_kind),
                  size: 18, color: scheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: Text(_label,
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              Text(_kind,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 12,
                  )),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        if (widget.node['role'] != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              widget.node['role'] as String,
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ),
        const Divider(height: 1),
        Expanded(child: _body(context)),
        if (_isEditable) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (_error != null)
                  Expanded(
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: (_dirty && !_saving) ? _save : null,
                  icon: _saving
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined, size: 16),
                  label: const Text('Save'),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _body(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && !_isEditable) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(_error!, style: const TextStyle(color: Colors.red)),
      );
    }
    if (_isGenerated) {
      if (_sources.isEmpty) {
        return const Padding(
          padding: EdgeInsets.all(16),
          child: Text('(no source mapping registered for this node)'),
        );
      }
      return ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _sources.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, i) {
          final s = _sources[i];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                s['label'] ?? '',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              if ((s['path'] ?? '').isNotEmpty)
                Text(
                  s['path']!,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.black54,
                  ),
                ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F7F7),
                  border: Border.all(color: const Color(0xFFE0E0E0)),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: SelectableText(
                  s['body'] ?? '',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          );
        },
      );
    }
    // file / human_override → editable text field.
    return Padding(
      padding: const EdgeInsets.all(12),
      child: TextField(
        controller: _ctrl,
        maxLines: null,
        expands: true,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }

  IconData _iconForKind(String kind) {
    switch (kind) {
      case 'file':
        return Icons.description_outlined;
      case 'generated':
        return Icons.settings_suggest_outlined;
      case 'human_override':
        return Icons.person_outline;
      default:
        return Icons.help_outline;
    }
  }
}
