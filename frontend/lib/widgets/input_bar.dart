import 'package:flutter/material.dart';

/// Horizontal strip rendered above the agent graph that surfaces the
/// council's input nodes (kind: file / generated / human_override).
///
/// Behavior:
/// - With nothing focused, every input is shown in manifest order.
/// - When an LLM agent is focused, inputs are sorted left→right in the
///   order they appear in the agent's `context_refs`; the rest fall to
///   the right and render grayed-out.
/// - When the focused node is a code node, inputs that resource-edge
///   into it move to the left; others gray out.
/// - For `generated` inputs, the producing script (the `source` field
///   on the node) is shown as a small chip pinned above the tile.
class InputBar extends StatelessWidget {
  const InputBar({
    super.key,
    required this.nodes,
    required this.edges,
    required this.focusedNodeId,
    this.onInputTap,
    this.onScriptTap,
  });

  final List<Map<String, dynamic>> nodes;
  final List<Map<String, dynamic>> edges;
  final String? focusedNodeId;
  final void Function(Map<String, dynamic> node)? onInputTap;
  // Fired when the user taps the small purple script chip above a
  // `generated` input. The node passed in is the *generated input*
  // itself; its id is what the source endpoint expects.
  final void Function(Map<String, dynamic> node)? onScriptTap;

  static const _inputKinds = {'file', 'generated', 'human_override'};

  @override
  Widget build(BuildContext context) {
    final inputs = [
      for (final n in nodes)
        if (_inputKinds.contains(n['kind'] as String?)) n,
    ];
    if (inputs.isEmpty) return const SizedBox.shrink();

    final focusedNode = focusedNodeId == null
        ? null
        : nodes.firstWhere(
            (n) => n['id'] == focusedNodeId,
            orElse: () => const <String, dynamic>{},
          );
    final isFocusOnAgent = focusedNode != null &&
        focusedNode.isNotEmpty &&
        !_inputKinds.contains(focusedNode['kind']);

    final (ordered, activeIds) =
        _orderAndActive(inputs, focusedNode, isFocusOnAgent);

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF7F8FA),
        border: Border(bottom: BorderSide(color: Color(0xFFE0E0E0))),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _Header(focusedNode: isFocusOnAgent ? focusedNode : null),
          const SizedBox(height: 6),
          SizedBox(
            height: 92,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: ordered.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final n = ordered[i];
                final id = n['id'] as String;
                final dimmed = isFocusOnAgent && !activeIds.contains(id);
                final orderIdx = isFocusOnAgent && activeIds.contains(id)
                    ? activeIds.toList().indexOf(id) + 1
                    : null;
                return _InputCard(
                  node: n,
                  dimmed: dimmed,
                  orderIndex: orderIdx,
                  onTap: dimmed ? null : () => onInputTap?.call(n),
                  onScriptTap:
                      dimmed ? null : () => onScriptTap?.call(n),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Returns the ordered list of input nodes and the set of ids considered
  /// "active" (feeding the focused agent). Order:
  /// 1. active inputs in `context_refs` order (LLM) or resource-edge order
  ///    (code) — fallback to manifest order if `context_refs` is missing.
  /// 2. remaining inputs in manifest order, rendered dimmed.
  (List<Map<String, dynamic>>, Set<String>) _orderAndActive(
    List<Map<String, dynamic>> inputs,
    Map<String, dynamic>? focusedNode,
    bool isFocusOnAgent,
  ) {
    if (!isFocusOnAgent || focusedNode == null) {
      return (inputs, <String>{});
    }
    final inputsById = {for (final n in inputs) n['id'] as String: n};
    final focusedId = focusedNode['id'] as String;

    final List<String> orderedRefs;
    final refs = focusedNode['context_refs'];
    if (refs is List && refs.isNotEmpty) {
      orderedRefs = [for (final r in refs) if (r is String) r];
    } else {
      // Fallback: walk resource edges in declaration order.
      orderedRefs = [
        for (final e in edges)
          if (e['kind'] == 'resource' && e['dst'] == focusedId)
            e['src'] as String,
      ];
    }

    final active = <String>{};
    final ordered = <Map<String, dynamic>>[];
    for (final r in orderedRefs) {
      final node = inputsById[r];
      if (node == null || active.contains(r)) continue;
      ordered.add(node);
      active.add(r);
    }
    for (final n in inputs) {
      final id = n['id'] as String;
      if (!active.contains(id)) ordered.add(n);
    }
    return (ordered, active);
  }
}

class _Header extends StatelessWidget {
  const _Header({this.focusedNode});
  final Map<String, dynamic>? focusedNode;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasFocus = focusedNode != null;
    return Row(
      children: [
        Icon(Icons.input, size: 14, color: scheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Text(
          'Inputs',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
        if (hasFocus) ...[
          const SizedBox(width: 8),
          Icon(Icons.arrow_forward, size: 12, color: scheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              'feeding ${focusedNode!['label'] ?? focusedNode!['id']}',
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );
  }
}

class _InputCard extends StatelessWidget {
  const _InputCard({
    required this.node,
    required this.dimmed,
    required this.orderIndex,
    required this.onTap,
    required this.onScriptTap,
  });

  final Map<String, dynamic> node;
  final bool dimmed;
  // 1-based position in the feed-order, or null when not in active set.
  final int? orderIndex;
  final VoidCallback? onTap;
  final VoidCallback? onScriptTap;

  @override
  Widget build(BuildContext context) {
    final kind = (node['kind'] as String?) ?? '';
    final isGenerated = kind == 'generated';
    final source = isGenerated ? (node['source'] as String?) : null;
    final scriptName = source?.split('/').last;

    return Opacity(
      opacity: dimmed ? 0.35 : 1.0,
      child: SizedBox(
        width: 148,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (scriptName != null) ...[
              _ScriptChip(
                name: scriptName,
                fullPath: source!,
                onTap: onScriptTap,
              ),
              const SizedBox(height: 3),
              const _DownArrow(),
              const SizedBox(height: 2),
            ],
            _InputTile(
              node: node,
              dimmed: dimmed,
              orderIndex: orderIndex,
              onTap: onTap,
            ),
          ],
        ),
      ),
    );
  }
}

class _ScriptChip extends StatelessWidget {
  const _ScriptChip({
    required this.name,
    required this.fullPath,
    this.onTap,
  });
  final String name;
  final String fullPath;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: fullPath,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFEDE7F6),
              border: Border.all(color: const Color(0xFFB39DDB)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.code, size: 11, color: Colors.black87),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    name,
                    style: const TextStyle(
                      fontSize: 10,
                      fontFamily: 'monospace',
                      color: Colors.black87,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DownArrow extends StatelessWidget {
  const _DownArrow();
  @override
  Widget build(BuildContext context) {
    return const Icon(
      Icons.arrow_downward,
      size: 10,
      color: Color(0xFF9E9E9E),
    );
  }
}

class _InputTile extends StatelessWidget {
  const _InputTile({
    required this.node,
    required this.dimmed,
    required this.orderIndex,
    required this.onTap,
  });

  final Map<String, dynamic> node;
  final bool dimmed;
  final int? orderIndex;
  final VoidCallback? onTap;

  Color _bg(String kind) {
    switch (kind) {
      case 'file':
        return const Color(0xFFE3F2FD);
      case 'generated':
        return const Color(0xFFE0F2F1);
      case 'human_override':
        return const Color(0xFFFFE0B2);
      default:
        return const Color(0xFFE0E0E0);
    }
  }

  IconData _icon(String kind) {
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

  @override
  Widget build(BuildContext context) {
    final kind = (node['kind'] as String?) ?? '';
    final label = (node['label'] as String?) ?? (node['id'] as String);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: _bg(kind),
            border: Border.all(color: Colors.black87, width: 1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              Icon(_icon(kind), size: 14, color: Colors.black87),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (orderIndex != null) ...[
                const SizedBox(width: 4),
                Container(
                  width: 16,
                  height: 16,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: Color(0xFF34495E),
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$orderIndex',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
