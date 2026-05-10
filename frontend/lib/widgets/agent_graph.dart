import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Renders the static council topology with per-round overlay metrics.
///
/// Nodes are positioned by normalized (x, y) coordinates from the
/// backend's topology.py. Each node's outline thickness is scaled by
/// LLM call count, its fill by approximate token volume, and tap
/// fires the optional [onAgentTap].
class AgentGraph extends StatelessWidget {
  const AgentGraph({
    super.key,
    required this.nodes,
    required this.edges,
    required this.overlay,
    this.onAgentTap,
  });

  final List<Map<String, dynamic>> nodes;
  final List<Map<String, dynamic>> edges;
  final Map<String, Map<String, dynamic>> overlay;
  final void Function(String agentId)? onAgentTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return GestureDetector(
          onTapUp: (details) {
            final hit = _hitTest(details.localPosition, size);
            if (hit != null && onAgentTap != null) onAgentTap!(hit);
          },
          child: CustomPaint(
            size: size,
            painter: _GraphPainter(
              nodes: nodes,
              edges: edges,
              overlay: overlay,
              theme: Theme.of(context),
            ),
          ),
        );
      },
    );
  }

  String? _hitTest(Offset p, Size size) {
    for (final n in nodes) {
      final c = Offset((n['x'] as num) * size.width, (n['y'] as num) * size.height);
      if ((c - p).distance <= 56) return n['id'] as String;
    }
    return null;
  }
}

class _GraphPainter extends CustomPainter {
  _GraphPainter({
    required this.nodes,
    required this.edges,
    required this.overlay,
    required this.theme,
  });

  final List<Map<String, dynamic>> nodes;
  final List<Map<String, dynamic>> edges;
  final Map<String, Map<String, dynamic>> overlay;
  final ThemeData theme;

  @override
  void paint(Canvas canvas, Size size) {
    final nodeById = {for (final n in nodes) n['id'] as String: n};
    final maxTokens = _maxTokens();

    // Edges first.
    for (final e in edges) {
      final src = nodeById[e['src']];
      final dst = nodeById[e['dst']];
      if (src == null || dst == null) continue;
      final p1 = _center(src, size);
      final p2 = _center(dst, size);
      _drawEdge(canvas, p1, p2, e['label'] as String);
    }

    // Nodes.
    for (final n in nodes) {
      final id = n['id'] as String;
      final c = _center(n, size);
      final ov = overlay[id];
      final tokens = (ov?['approx_tokens'] as num?)?.toDouble() ?? 0.0;
      final calls = (ov?['calls'] as num?)?.toInt() ?? 0;
      final wall = (ov?['wall_seconds'] as num?)?.toDouble() ?? 0.0;
      final isLLM = n['kind'] == 'llm';
      final fill = _fillColor(isLLM, tokens, maxTokens);
      final stroke = isLLM ? theme.colorScheme.primary : theme.colorScheme.outline;
      final r = 52.0 + math.min(calls.toDouble() * 4.0, 16.0);
      canvas.drawCircle(c, r, Paint()..color = fill);
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = isLLM ? 2.5 + math.min(calls.toDouble(), 4) : 2.0
          ..color = stroke,
      );
      _drawNodeLabel(canvas, c, n['label'] as String, calls, tokens, wall);
    }
  }

  double _maxTokens() {
    double m = 1.0;
    for (final v in overlay.values) {
      final t = (v['approx_tokens'] as num?)?.toDouble() ?? 0.0;
      if (t > m) m = t;
    }
    return m;
  }

  Color _fillColor(bool isLLM, double tokens, double maxTokens) {
    if (!isLLM) return theme.colorScheme.surfaceContainerHighest;
    final t = (tokens / maxTokens).clamp(0.0, 1.0);
    return Color.lerp(
          theme.colorScheme.primaryContainer,
          theme.colorScheme.primary,
          t * 0.6,
        ) ??
        theme.colorScheme.primaryContainer;
  }

  Offset _center(Map<String, dynamic> n, Size s) =>
      Offset((n['x'] as num) * s.width, (n['y'] as num) * s.height);

  void _drawEdge(Canvas canvas, Offset a, Offset b, String label) {
    final paint = Paint()
      ..color = theme.colorScheme.outlineVariant
      ..strokeWidth = 1.5;
    canvas.drawLine(a, b, paint);
    // Arrowhead.
    final dir = (b - a);
    final len = dir.distance;
    if (len <= 0) return;
    final unit = dir / len;
    final tip = b - unit * 56;
    final perp = Offset(-unit.dy, unit.dx);
    final left = tip - unit * 8 + perp * 6;
    final right = tip - unit * 8 - perp * 6;
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(left.dx, left.dy)
      ..lineTo(right.dx, right.dy)
      ..close();
    canvas.drawPath(path, Paint()..color = theme.colorScheme.outline);

    // Label near midpoint.
    final mid = (a + b) / 2;
    _text(canvas, mid + const Offset(8, 8), label, theme.textTheme.labelSmall);
  }

  void _drawNodeLabel(
      Canvas canvas, Offset c, String label, int calls, double tokens, double wall) {
    _text(canvas, c + const Offset(0, -8), label,
        theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        align: TextAlign.center, maxWidth: 140);
    final sub = calls == 0
        ? '—'
        : '$calls call${calls == 1 ? '' : 's'}'
            ' · ≈${_fmt(tokens)} tok'
            ' · ${wall.toStringAsFixed(0)}s';
    _text(canvas, c + const Offset(0, 14), sub,
        theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        align: TextAlign.center, maxWidth: 160);
  }

  void _text(Canvas canvas, Offset p, String s, TextStyle? style,
      {TextAlign align = TextAlign.left, double? maxWidth}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: style),
      textDirection: TextDirection.ltr,
      textAlign: align,
      maxLines: 2,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth ?? 200);
    final dx = align == TextAlign.center ? p.dx - tp.width / 2 : p.dx;
    tp.paint(canvas, Offset(dx, p.dy));
  }

  String _fmt(double v) {
    if (v >= 1e6) return '${(v / 1e6).toStringAsFixed(1)}M';
    if (v >= 1e3) return '${(v / 1e3).toStringAsFixed(1)}k';
    return v.toStringAsFixed(0);
  }

  @override
  bool shouldRepaint(_GraphPainter old) =>
      old.nodes != nodes || old.edges != edges || old.overlay != overlay;
}
