import 'package:flutter/material.dart';

/// Pastel color per feature family + a [FeatureChip] that renders one
/// scalar id with the family prefix stripped and the pill tinted by
/// family. Shared so candidate lists, performance tables, and round
/// Results columns all visually agree on family identity.

/// Family prefix → pastel background color for the pill.
const Map<String, Color> kFeatureFamilyColors = {
  'geom': Color(0xFFC8E6C9), // pastel green
  'topo': Color(0xFFE1BEE7), // pastel lavender
  'chem': Color(0xFFFFE0B2), // pastel orange
  'embed': Color(0xFFBBDEFB), // pastel blue (reserved)
  'phys': Color(0xFFFFCDD2), // pastel red (reserved)
};
const Color kFeatureFamilyDefaultColor = Color(0xFFE0E0E0); // pastel grey

/// First dotted segment of a scalar id (``geom.surf_area.total`` →
/// ``geom``). Whole string if no dot.
String featureFamily(String fid) {
  final i = fid.indexOf('.');
  return i < 0 ? fid : fid.substring(0, i);
}

/// Scalar id with the family prefix removed.
String stripFamily(String fid) {
  final i = fid.indexOf('.');
  return i < 0 ? fid : fid.substring(i + 1);
}

Color featureFamilyColor(String family) =>
    kFeatureFamilyColors[family] ?? kFeatureFamilyDefaultColor;

/// A single feature pill — pastel family color, stripped scalar name,
/// dense for fitting in tight columns / cards.
class FeatureChip extends StatelessWidget {
  const FeatureChip({super.key, required this.featureId});

  final String featureId;

  @override
  Widget build(BuildContext context) {
    final family = featureFamily(featureId);
    final color = featureFamilyColor(family);
    return Tooltip(
      message: featureId,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          stripFamily(featureId),
          style: const TextStyle(
            color: Colors.black87,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

/// Wrap a list of feature ids as pastel pills. ``maxWidth`` constrains
/// horizontal extent for use inside DataTable cells.
class FeatureChipList extends StatelessWidget {
  const FeatureChipList({
    super.key,
    required this.featureIds,
    this.maxWidth,
  });

  final List<String> featureIds;
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    final child = Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [for (final f in featureIds) FeatureChip(featureId: f)],
    );
    if (maxWidth == null) return child;
    return SizedBox(width: maxWidth, child: child);
  }
}
