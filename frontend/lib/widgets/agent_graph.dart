import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Renders the council topology with per-round overlay metrics.
///
/// Tiles start at normalized (x, y) coordinates from the backend's
/// topology.py and can be dragged. Tap fires [onAgentTap]. Edges are
/// repainted as tiles move.
class AgentGraph extends StatefulWidget {
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
  State<AgentGraph> createState() => _AgentGraphState();
}

const double _tileW = 168.0;
const double _tileH = 78.0;
const double _tileWNon = 110.0;
const double _tileHNon = 50.0;
const Color _bgColor = Color(0xFF34495E);
const Color _tileColor = Color(0xFFFFF59D);
const Color _nonAgentTileColor = Color(0xFFE0E0E0);
const Color _edgeColor = Color(0xCCFFFFFF);

Size _sizeFor(bool isLLM) =>
    isLLM ? const Size(_tileW, _tileH) : const Size(_tileWNon, _tileHNon);

class _AgentGraphState extends State<AgentGraph> {
  final Map<String, Offset> _positions = {};

  void _ensurePositions(Size size) {
    final sized = size.width > 0 && size.height > 0;
    if (!sized) return;
    for (final n in widget.nodes) {
      final id = n['id'] as String;
      if (!_positions.containsKey(id)) {
        _positions[id] = Offset(
          (n['x'] as num).toDouble() * size.width,
          (n['y'] as num).toDouble() * size.height,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final size = Size(constraints.maxWidth, constraints.maxHeight);
      _ensurePositions(size);
      final maxTokens = _maxTokens();

      final sizes = <String, Size>{
        for (final n in widget.nodes)
          n['id'] as String: _sizeFor(n['kind'] == 'llm'),
      };

      final labels = _layoutEdgeLabels(sizes);

      return Container(
        color: _bgColor,
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _EdgePainter(
                  edges: widget.edges,
                  positions: Map<String, Offset>.from(_positions),
                  sizes: sizes,
                ),
              ),
            ),
            for (final l in labels) _EdgeLabelChip(label: l),
            for (final n in widget.nodes) _buildTile(n, maxTokens, size),
          ],
        ),
      );
    });
  }

  /// Compute the midpoint + perpendicular offset for every edge label.
  ///
  /// Each label sits 18px to the LEFT of its directed edge (perpendicular
  /// to the direction, CCW). For a bidirectional pair like
  /// decider↔master_critic, the two directions have opposite unit
  /// vectors, so their perpendiculars are opposite too — the two labels
  /// end up on opposite sides of the line without any pair-counting
  /// bookkeeping. The previous attempt also flipped a per-pair sign,
  /// which double-flipped and put both labels back on the same spot.
  List<_LabelLayout> _layoutEdgeLabels(Map<String, Size> sizes) {
    const double offset = 18.0;
    final out = <_LabelLayout>[];
    for (final e in widget.edges) {
      final src = e['src'] as String;
      final dst = e['dst'] as String;
      final a = _positions[src];
      final b = _positions[dst];
      if (a == null || b == null) continue;
      final aSize = sizes[src] ?? const Size(_tileW, _tileH);
      final bSize = sizes[dst] ?? const Size(_tileW, _tileH);

      final dir = b - a;
      final len = dir.distance;
      if (len <= 0) continue;
      final unit = dir / len;
      final aClip = a + unit * _clipDist(unit, aSize);
      final bClip = b - unit * _clipDist(unit, bSize);
      final mid = (aClip + bClip) / 2;
      final perpLeft = Offset(-unit.dy, unit.dx);
      out.add(_LabelLayout(
        text: e['label'] as String,
        pos: mid + perpLeft * offset,
      ));
    }
    return out;
  }

  double _clipDist(Offset u, Size tile) {
    final ax = u.dx.abs();
    final ay = u.dy.abs();
    final hw = tile.width / 2;
    final hh = tile.height / 2;
    final tx = ax > 1e-9 ? hw / ax : double.infinity;
    final ty = ay > 1e-9 ? hh / ay : double.infinity;
    return math.min(tx, ty);
  }

  Widget _buildTile(Map<String, dynamic> n, double maxTokens, Size size) {
    final id = n['id'] as String;
    final pos = _positions[id] ?? Offset.zero;
    final ov = widget.overlay[id];
    final tokens = (ov?['approx_tokens'] as num?)?.toDouble() ?? 0.0;
    final calls = (ov?['calls'] as num?)?.toInt() ?? 0;
    final wall = (ov?['wall_seconds'] as num?)?.toDouble() ?? 0.0;
    final active = (ov?['active'] as bool?) ?? false;
    final isLLM = n['kind'] == 'llm';
    final tileSize = _sizeFor(isLLM);
    final hw = tileSize.width / 2;
    final hh = tileSize.height / 2;
    final (statusColor, statusText) = _statusFor(active, calls, isLLM);

    return Positioned(
      left: pos.dx - hw,
      top: pos.dy - hh,
      width: tileSize.width,
      height: tileSize.height,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onAgentTap?.call(id),
        onPanUpdate: (d) {
          setState(() {
            final next = (_positions[id] ?? pos) + d.delta;
            final clamped = Offset(
              next.dx.clamp(hw, math.max(hw, size.width - hw)),
              next.dy.clamp(hh, math.max(hh, size.height - hh)),
            );
            _positions[id] = clamped;
          });
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.move,
          child: Container(
            decoration: BoxDecoration(
              color: isLLM ? _tileColor : _nonAgentTileColor,
              border: Border.all(
                color: active ? Colors.lightBlueAccent : Colors.black87,
                width: active ? 2.5 : 1.5,
              ),
              borderRadius: BorderRadius.circular(6),
              boxShadow: const [
                BoxShadow(color: Color(0x55000000), blurRadius: 4, offset: Offset(0, 2)),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    color: statusColor,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 1),
                    child: Text(
                      statusText,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            n['label'] as String,
                            style: const TextStyle(
                              color: Colors.black,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                          if (isLLM) ...[
                            const SizedBox(height: 2),
                            Text(
                              calls == 0
                                  ? '—'
                                  : '$calls · ≈${_fmt(tokens)} tok · ${wall.toStringAsFixed(0)}s',
                              style: const TextStyle(
                                  color: Colors.black87, fontSize: 11),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  (Color, String) _statusFor(bool active, int calls, bool isLLM) {
    if (!isLLM) return (const Color(0xFF607D8B), 'code');
    if (active) return (const Color(0xFF2196F3), 'running');
    if (calls > 0) return (const Color(0xFF4CAF50), 'done');
    return (const Color(0xFF757575), 'idle');
  }

  double _maxTokens() {
    double m = 1.0;
    for (final v in widget.overlay.values) {
      final t = (v['approx_tokens'] as num?)?.toDouble() ?? 0.0;
      if (t > m) m = t;
    }
    return m;
  }

  String _fmt(double v) {
    if (v >= 1e6) return '${(v / 1e6).toStringAsFixed(1)}M';
    if (v >= 1e3) return '${(v / 1e3).round()}k';
    return v.toStringAsFixed(0);
  }
}

class _EdgePainter extends CustomPainter {
  _EdgePainter({
    required this.edges,
    required this.positions,
    required this.sizes,
  });

  final List<Map<String, dynamic>> edges;
  final Map<String, Offset> positions;
  final Map<String, Size> sizes;

  @override
  void paint(Canvas canvas, Size size) {
    for (final e in edges) {
      final srcId = e['src'] as String;
      final dstId = e['dst'] as String;
      final a = positions[srcId];
      final b = positions[dstId];
      if (a == null || b == null) continue;
      final aSize = sizes[srcId] ?? const Size(_tileW, _tileH);
      final bSize = sizes[dstId] ?? const Size(_tileW, _tileH);
      _drawEdge(canvas, a, b, aSize, bSize, e['label'] as String);
    }
  }

  void _drawEdge(
      Canvas canvas, Offset a, Offset b, Size aSize, Size bSize, String label) {
    final dir = b - a;
    final len = dir.distance;
    if (len <= 0) return;
    final unit = dir / len;
    final aClip = a + unit * _clipDist(unit, aSize);
    final bClip = b - unit * _clipDist(unit, bSize);

    canvas.drawLine(
      aClip,
      bClip,
      Paint()
        ..color = _edgeColor
        ..strokeWidth = 1.5,
    );

    final perp = Offset(-unit.dy, unit.dx);
    final back = bClip - unit * 9;
    final left = back + perp * 6;
    final right = back - perp * 6;
    final path = Path()
      ..moveTo(bClip.dx, bClip.dy)
      ..lineTo(left.dx, left.dy)
      ..lineTo(right.dx, right.dy)
      ..close();
    canvas.drawPath(path, Paint()..color = _edgeColor);
    // Labels are drawn as widgets in the Stack — see _EdgeLabelChip —
    // so they sit above the edge canvas with a real white background
    // and aren't covered by line / arrowhead pixels.
  }

  double _clipDist(Offset u, Size tile) {
    final ax = u.dx.abs();
    final ay = u.dy.abs();
    final hw = tile.width / 2;
    final hh = tile.height / 2;
    final tx = ax > 1e-9 ? hw / ax : double.infinity;
    final ty = ay > 1e-9 ? hh / ay : double.infinity;
    return math.min(tx, ty);
  }

  @override
  bool shouldRepaint(_EdgePainter old) => true;
}

class _LabelLayout {
  const _LabelLayout({required this.text, required this.pos});
  final String text;
  final Offset pos;
}

class _EdgeLabelChip extends StatelessWidget {
  const _EdgeLabelChip({required this.label});
  final _LabelLayout label;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: label.pos.dx,
      top: label.pos.dy,
      child: FractionalTranslation(
        translation: const Offset(-0.5, -0.5),
        child: IgnorePointer(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: const Color(0xFFB0B0B0), width: 1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              label.text,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }
}
