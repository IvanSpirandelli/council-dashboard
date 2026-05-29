import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Renders the council topology with per-round overlay metrics.
///
/// Tiles start at normalized (x, y) coordinates from the backend's
/// topology.py and can be dragged. Tap fires [onAgentTap]. Edges are
/// repainted as tiles move.
/// Imperative handle for the parent page to read the current layout and
/// observe / drive the currently focused node.
class AgentGraphController {
  AgentGraphState? _state;

  /// Currently focused node id (the one the user last tapped). Null when
  /// nothing is focused. Listen to drive sibling widgets (e.g. the input
  /// bar that re-sorts based on which agent is selected).
  final ValueNotifier<String?> focusedNodeId = ValueNotifier<String?>(null);

  /// Returns the latest node positions normalized to 0–1 by the current
  /// container size, or null if the graph hasn't been laid out yet.
  Map<String, ({double x, double y})>? snapshotNormalized() =>
      _state?.snapshotNormalized();

  void clearFocus() => focusedNodeId.value = null;

  void dispose() {
    focusedNodeId.dispose();
  }
}

class AgentGraph extends StatefulWidget {
  const AgentGraph({
    super.key,
    required this.nodes,
    required this.edges,
    required this.overlay,
    this.onAgentTap,
    this.controller,
  });

  final List<Map<String, dynamic>> nodes;
  final List<Map<String, dynamic>> edges;
  final Map<String, Map<String, dynamic>> overlay;
  final void Function(String agentId)? onAgentTap;
  final AgentGraphController? controller;

  @override
  State<AgentGraph> createState() => AgentGraphState();
}

const double _tileW = 168.0;
const double _tileH = 82.0;
const double _tileWNon = 110.0;
const double _tileHNon = 54.0;
const Color _bgColor = Color(0xFF34495E);
const Color _tileColor = Color(0xFFFFF59D);
const Color _nonAgentTileColor = Color(0xFFE0E0E0);
const Color _fileTileColor = Color(0xFFE3F2FD);
const Color _generatedTileColor = Color(0xFFE0F2F1);
const Color _humanOverrideTileColor = Color(0xFFFFE0B2);
const Color _edgeColor = Color(0xCCFFFFFF);
const Color _resourceEdgeColor = Color(0x88FFFFFF);

bool _isInputKind(String kind) =>
    kind == 'file' || kind == 'generated' || kind == 'human_override';

Size _sizeFor(String kind) =>
    kind == 'llm' ? const Size(_tileW, _tileH) : const Size(_tileWNon, _tileHNon);

Color _tileColorFor(String kind) {
  switch (kind) {
    case 'llm':
      return _tileColor;
    case 'file':
      return _fileTileColor;
    case 'generated':
      return _generatedTileColor;
    case 'human_override':
      return _humanOverrideTileColor;
    default:
      return _nonAgentTileColor;
  }
}

IconData _iconForKind(String kind) {
  switch (kind) {
    case 'llm':
      return Icons.smart_toy_outlined;
    case 'file':
      return Icons.description_outlined;
    case 'generated':
      return Icons.settings_suggest_outlined;
    case 'human_override':
      return Icons.person_outline;
    default:
      return Icons.code;
  }
}

class AgentGraphState extends State<AgentGraph> {
  final Map<String, Offset> _positions = {};
  Size _lastSize = Size.zero;
  // Fallback focus state used when no controller is attached. With a
  // controller, the controller's ValueNotifier is the source of truth.
  String? _localFocusedNodeId;

  String? get _focusedNodeId =>
      widget.controller?.focusedNodeId.value ?? _localFocusedNodeId;

  void _setFocus(String? id) {
    final c = widget.controller;
    if (c != null) {
      // The listener registered in initState/didUpdateWidget rebuilds us.
      c.focusedNodeId.value = id;
    } else {
      setState(() => _localFocusedNodeId = id);
    }
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    widget.controller?._state = this;
    widget.controller?.focusedNodeId.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(AgentGraph oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._state = null;
      oldWidget.controller?.focusedNodeId.removeListener(_onFocusChanged);
      widget.controller?._state = this;
      widget.controller?.focusedNodeId.addListener(_onFocusChanged);
    }
  }

  @override
  void dispose() {
    widget.controller?._state = null;
    widget.controller?.focusedNodeId.removeListener(_onFocusChanged);
    super.dispose();
  }

  /// Latest positions normalized against the most-recently-laid-out size.
  /// Returns null until the widget has been laid out at least once.
  Map<String, ({double x, double y})>? snapshotNormalized() {
    if (_lastSize.width <= 0 || _lastSize.height <= 0) return null;
    return {
      for (final entry in _positions.entries)
        entry.key: (
          x: entry.value.dx / _lastSize.width,
          y: entry.value.dy / _lastSize.height,
        ),
    };
  }

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
      _lastSize = size;
      _ensurePositions(size);
      final maxTokens = _maxTokens();

      final sizes = <String, Size>{
        for (final n in widget.nodes)
          n['id'] as String: _sizeFor((n['kind'] as String?) ?? 'llm'),
      };

      // Resource edges (kind: resource) are hidden by default and only
      // drawn when one of their endpoints is the focused node. Flow edges
      // (no kind, or kind != 'resource') are always drawn.
      final visibleEdges = _visibleEdges();
      final lateral = _edgeLateralOffsets(visibleEdges);
      final labels = _layoutEdgeLabels(visibleEdges, sizes, lateral);
      final highlighted = _highlightedNodeIds();

      return Container(
        color: _bgColor,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (_focusedNodeId != null) _setFocus(null);
          },
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _EdgePainter(
                    edges: visibleEdges,
                    positions: Map<String, Offset>.from(_positions),
                    sizes: sizes,
                    lateralOffsets: lateral,
                  ),
                ),
              ),
              for (final l in labels) _EdgeLabelChip(label: l),
              for (final n in widget.nodes)
                _buildTile(n, maxTokens, size, highlighted),
            ],
          ),
        ),
      );
    });
  }

  /// Edges to actually draw given the current focus. Resource edges
  /// only show when the focused node is one of their endpoints.
  List<Map<String, dynamic>> _visibleEdges() {
    return [
      for (final e in widget.edges)
        if (e['kind'] != 'resource' ||
            (_focusedNodeId != null &&
                (e['src'] == _focusedNodeId || e['dst'] == _focusedNodeId)))
          e,
    ];
  }

  /// Nodes that should render with a highlight border (the focused node
  /// itself plus any node it's connected to via a resource edge).
  Set<String> _highlightedNodeIds() {
    final focused = _focusedNodeId;
    if (focused == null) return const {};
    final out = <String>{focused};
    for (final e in widget.edges) {
      if (e['kind'] != 'resource') continue;
      if (e['src'] == focused) out.add(e['dst'] as String);
      if (e['dst'] == focused) out.add(e['src'] as String);
    }
    return out;
  }

  /// Per-edge lateral offset so that a pair of edges in opposite
  /// directions between the same two nodes (e.g. decider↔master_critic)
  /// renders as two parallel arrows instead of one line drawn twice.
  Map<int, double> _edgeLateralOffsets(List<Map<String, dynamic>> edges) {
    const double sep = 9.0;
    final out = <int, double>{};
    final pairs = <String, int>{};
    for (var i = 0; i < edges.length; i++) {
      final src = edges[i]['src'] as String;
      final dst = edges[i]['dst'] as String;
      pairs['$src→$dst'] = i;
    }
    final used = <int>{};
    for (var i = 0; i < edges.length; i++) {
      if (used.contains(i)) continue;
      final src = edges[i]['src'] as String;
      final dst = edges[i]['dst'] as String;
      final reverseIdx = pairs['$dst→$src'];
      if (reverseIdx != null && reverseIdx != i) {
        // Both edges shift to their own perpLeft side by sep/2.
        out[i] = sep / 2;
        out[reverseIdx] = sep / 2;
        used..add(i)..add(reverseIdx);
      }
    }
    return out;
  }

  /// Compute the anchor point + perpendicular direction for every edge
  /// label. The chip is then rendered so that its *inner edge* (the side
  /// facing the line) sits at the anchor, with the rest of the chip
  /// extending outward in the perpendicular direction. This is what
  /// stops the decider↔critic chips overlapping — their inner edges
  /// pin to the same line but on opposite sides, so the chip bodies
  /// can't collide regardless of how wide the text is.
  List<_LabelLayout> _layoutEdgeLabels(
      List<Map<String, dynamic>> edges,
      Map<String, Size> sizes,
      Map<int, double> lateral) {
    // Tiny breathing room between chip and line.
    const double gap = 3.0;
    final out = <_LabelLayout>[];
    for (var i = 0; i < edges.length; i++) {
      final e = edges[i];
      final src = e['src'] as String;
      final dst = e['dst'] as String;
      // Resource edges are unlabeled (the source node identifies the
      // resource), so skip label layout for them.
      if (e['kind'] == 'resource') continue;
      final label = e['label'];
      if (label == null) continue;
      final a = _positions[src];
      final b = _positions[dst];
      if (a == null || b == null) continue;
      final aSize = sizes[src] ?? const Size(_tileW, _tileH);
      final bSize = sizes[dst] ?? const Size(_tileW, _tileH);

      final dir = b - a;
      final len = dir.distance;
      if (len <= 0) continue;
      final unit = dir / len;
      final perpLeft = Offset(-unit.dy, unit.dx);
      final shift = perpLeft * (lateral[i] ?? 0);
      final aClip = a + unit * _clipDist(unit, aSize) + shift;
      final bClip = b - unit * _clipDist(unit, bSize) + shift;
      final mid = (aClip + bClip) / 2;
      out.add(_LabelLayout(
        text: label as String,
        anchor: mid + perpLeft * gap,
        perp: perpLeft,
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

  Widget _buildTile(Map<String, dynamic> n, double maxTokens, Size size,
      Set<String> highlighted) {
    final id = n['id'] as String;
    final pos = _positions[id] ?? Offset.zero;
    final ov = widget.overlay[id];
    final tokens = (ov?['approx_tokens'] as num?)?.toDouble() ?? 0.0;
    final calls = (ov?['calls'] as num?)?.toInt() ?? 0;
    final wall = (ov?['wall_seconds'] as num?)?.toDouble() ?? 0.0;
    final active = (ov?['active'] as bool?) ?? false;
    final done = (ov?['done'] as bool?) ?? false;
    final kind = (n['kind'] as String?) ?? 'llm';
    final isLLM = kind == 'llm';
    final isInput = _isInputKind(kind);
    final tileSize = _sizeFor(kind);
    final hw = tileSize.width / 2;
    final hh = tileSize.height / 2;
    // Prefer the backend-computed lifecycle string when present; fall back
    // to local derivation for old payloads. Input nodes have no lifecycle —
    // they're static resources, so the header strip is omitted for them.
    final state = (ov?['state'] as String?) ??
        _localState(isLLM: isLLM, active: active, calls: calls, done: done);
    final statusColor = _colorForState(state);
    final icon = _iconForKind(kind);
    final tileColor = _tileColorFor(kind);
    final isHighlighted = highlighted.contains(id);
    final borderColor = active
        ? Colors.lightBlueAccent
        : (isHighlighted ? Colors.orange : Colors.black87);
    final borderWidth = active || isHighlighted ? 2.5 : 1.5;
    final chips = (n['chips'] as Map?)?.cast<String, dynamic>();

    return Positioned(
      left: pos.dx - hw,
      top: pos.dy - hh,
      width: tileSize.width,
      height: tileSize.height,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          // Toggling focus drives the in-graph highlight overlay and is
          // also exposed via the controller for sibling widgets (input
          // bar). LLM/code nodes still report up via onAgentTap so parent
          // pages can navigate or open dialogs.
          _setFocus(_focusedNodeId == id ? null : id);
          widget.onAgentTap?.call(id);
        },
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
              color: tileColor,
              border: Border.all(color: borderColor, width: borderWidth),
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
                  if (!isInput)
                    Container(
                      color: statusColor,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(icon, size: 11, color: Colors.white),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              state,
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
                        ],
                      ),
                    ),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                          horizontal: 8, vertical: isInput ? 2 : 3),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (isInput) ...[
                                Icon(icon, size: 12, color: Colors.black87),
                                const SizedBox(width: 4),
                              ],
                              Flexible(
                                child: Text(
                                  n['label'] as String,
                                  style: TextStyle(
                                    color: Colors.black,
                                    fontSize: isInput ? 11 : 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
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
                            if (chips != null && chips.isNotEmpty)
                              _ChipRow(chips: chips),
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

  String _localState({
    required bool isLLM,
    required bool active,
    required int calls,
    required bool done,
  }) {
    if (isLLM) {
      if (active) return 'working';
      if (calls > 0) return 'done';
      return 'idle';
    }
    if (active) return 'running';
    if (done) return 'done';
    return 'idle';
  }

  Color _colorForState(String state) {
    switch (state) {
      case 'working':
      case 'running':
        return const Color(0xFF2196F3);
      case 'done':
        return const Color(0xFF4CAF50);
      case 'failed':
        return const Color(0xFFE53935);
      default:
        return const Color(0xFF757575);
    }
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
    required this.lateralOffsets,
  });

  final List<Map<String, dynamic>> edges;
  final Map<String, Offset> positions;
  final Map<String, Size> sizes;
  // Edge index → perpendicular shift (px) so paired reverse edges render
  // as two parallel arrows instead of one overlapping line.
  final Map<int, double> lateralOffsets;

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < edges.length; i++) {
      final e = edges[i];
      final srcId = e['src'] as String;
      final dstId = e['dst'] as String;
      final a = positions[srcId];
      final b = positions[dstId];
      if (a == null || b == null) continue;
      final aSize = sizes[srcId] ?? const Size(_tileW, _tileH);
      final bSize = sizes[dstId] ?? const Size(_tileW, _tileH);
      _drawEdge(
        canvas, a, b, aSize, bSize,
        lateral: lateralOffsets[i] ?? 0,
        isResource: e['kind'] == 'resource',
      );
    }
  }

  void _drawEdge(
    Canvas canvas,
    Offset a,
    Offset b,
    Size aSize,
    Size bSize, {
    required double lateral,
    required bool isResource,
  }) {
    final dir = b - a;
    final len = dir.distance;
    if (len <= 0) return;
    final unit = dir / len;
    final perpLeft = Offset(-unit.dy, unit.dx);
    final shift = perpLeft * lateral;
    final aClip = a + unit * _clipDist(unit, aSize) + shift;
    final bClip = b - unit * _clipDist(unit, bSize) + shift;
    // Resource edges are thinner + dimmer + dashed: they're auxiliary
    // wiring shown only when a node is focused, and should sit visually
    // below the primary flow edges.
    final color = isResource ? _resourceEdgeColor : _edgeColor;
    final stroke = isResource ? 1.0 : 1.5;
    final paint = Paint()
      ..color = color
      ..strokeWidth = stroke;
    if (isResource) {
      _drawDashedLine(canvas, aClip, bClip, paint);
    } else {
      canvas.drawLine(aClip, bClip, paint);
    }

    final back = bClip - unit * 9;
    final left = back + perpLeft * 6;
    final right = back - perpLeft * 6;
    final path = Path()
      ..moveTo(bClip.dx, bClip.dy)
      ..lineTo(left.dx, left.dy)
      ..lineTo(right.dx, right.dy)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
    // Labels are drawn as widgets in the Stack — see _EdgeLabelChip —
    // so they sit above the edge canvas with a real white background
    // and aren't covered by line / arrowhead pixels.
  }

  void _drawDashedLine(Canvas canvas, Offset a, Offset b, Paint paint) {
    const double dash = 5.0;
    const double gap = 4.0;
    final delta = b - a;
    final total = delta.distance;
    if (total <= 0) return;
    final unit = delta / total;
    double travelled = 0.0;
    while (travelled < total) {
      final segEnd = math.min(travelled + dash, total);
      canvas.drawLine(a + unit * travelled, a + unit * segEnd, paint);
      travelled = segEnd + gap;
    }
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
  const _LabelLayout({
    required this.text,
    required this.anchor,
    required this.perp,
  });
  final String text;
  // The anchor is where the chip's inner edge (the side facing the
  // line) sits. The chip body extends outward in [perp]'s direction.
  final Offset anchor;
  final Offset perp;
}

class _EdgeLabelChip extends StatelessWidget {
  const _EdgeLabelChip({required this.label});
  final _LabelLayout label;

  @override
  Widget build(BuildContext context) {
    // FractionalTranslation shifts the chip by (tx * width, ty * height).
    // (0,0) keeps top-left at the anchor; (-1, -1) puts bottom-right at
    // the anchor; (-0.5, -0.5) centers. To anchor the inner edge to the
    // line, we want the chip's edge facing -perp at the anchor — i.e.
    // the chip extends in +perp from there. For a unit perp (px, py),
    // tx = -0.5 + 0.5 * px and ty = -0.5 + 0.5 * py produces:
    //   perp = ( 1,  0)  →  (tx, ty) = ( 0.0, -0.5)  ← left-middle on anchor
    //   perp = (-1,  0)  →  (tx, ty) = (-1.0, -0.5)  ← right-middle
    //   perp = ( 0,  1)  →  (tx, ty) = (-0.5,  0.0)  ← top-middle
    //   perp = ( 0, -1)  →  (tx, ty) = (-0.5, -1.0)  ← bottom-middle
    // and a smooth interpolation for diagonal perps.
    final tx = -0.5 + 0.5 * label.perp.dx;
    final ty = -0.5 + 0.5 * label.perp.dy;
    return Positioned(
      left: label.anchor.dx,
      top: label.anchor.dy,
      child: FractionalTranslation(
        translation: Offset(tx, ty),
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

/// Manifest-config chips rendered inline on an LLM agent tile
/// (e.g. n=10, max=22, sonnet). Kept tiny — these are read-only.
class _ChipRow extends StatelessWidget {
  const _ChipRow({required this.chips});
  final Map<String, dynamic> chips;

  @override
  Widget build(BuildContext context) {
    final pieces = <String>[];
    final n = chips['n_candidates'];
    if (n != null) pieces.add('n=$n');
    final mp = chips['max_promotions'];
    if (mp != null) pieces.add('max=$mp');
    final model = chips['model'];
    if (model is String && model.isNotEmpty) pieces.add(model);
    if (pieces.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 1),
      child: Text(
        pieces.join(' · '),
        style: const TextStyle(
          color: Colors.black54,
          fontSize: 10,
          fontWeight: FontWeight.w500,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
      ),
    );
  }
}
