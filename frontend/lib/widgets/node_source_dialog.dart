import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/providers.dart';

/// Read-only viewer for the Python that backs a node — either the
/// producing script of a `generated` input (opened from the script chip
/// in the input bar) or the implementation of a `code` node in the graph
/// (validator / executor).
///
/// Backed by the existing ``/councils/{name}/nodes/{node_id}/source``
/// endpoint, which returns a list of ``{label, path, body}`` blocks.
Future<void> showNodeSourceDialog(
  BuildContext context, {
  required String councilName,
  required String nodeId,
  required String title,
}) {
  return showDialog(
    context: context,
    builder: (_) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000, maxHeight: 760),
        child: _NodeSourceDialogBody(
          councilName: councilName,
          nodeId: nodeId,
          title: title,
        ),
      ),
    ),
  );
}

class _NodeSourceDialogBody extends ConsumerStatefulWidget {
  const _NodeSourceDialogBody({
    required this.councilName,
    required this.nodeId,
    required this.title,
  });

  final String councilName;
  final String nodeId;
  final String title;

  @override
  ConsumerState<_NodeSourceDialogBody> createState() =>
      _NodeSourceDialogBodyState();
}

class _NodeSourceDialogBodyState extends ConsumerState<_NodeSourceDialogBody> {
  bool _loading = true;
  String? _error;
  List<Map<String, String>> _sources = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await ref
          .read(dashboardApiProvider)
          .councilNodeSource(widget.councilName, widget.nodeId);
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
    } catch (e) {
      setState(() {
        _loading = false;
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
              Icon(Icons.code, size: 18, color: scheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: Text(widget.title,
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(child: _body(context)),
      ],
    );
  }

  Widget _body(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(_error!, style: const TextStyle(color: Colors.red)),
      );
    }
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
                style: const TextStyle(fontSize: 11, color: Colors.black54),
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
}
