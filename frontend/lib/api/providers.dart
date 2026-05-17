import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'client.dart';

final dashboardApiProvider = Provider<DashboardApi>((ref) {
  final api = DashboardApi();
  ref.onDispose(api.close);
  return api;
});

final healthProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  return ref.watch(dashboardApiProvider).health();
});

// ── Councils ──────────────────────────────────────────────────────────

final councilsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  return ref.watch(dashboardApiProvider).councils();
});

final councilProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, name) async {
  return ref.watch(dashboardApiProvider).council(name);
});

final councilTopologyProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, name) async {
  return ref.watch(dashboardApiProvider).councilTopology(name);
});

final councilSessionProvider =
    FutureProvider.family<Map<String, dynamic>, String>((ref, name) async {
  return ref.watch(dashboardApiProvider).councilSession(name);
});

class CouncilRoundKey {
  const CouncilRoundKey(this.councilName, this.roundId);
  final String councilName;
  final String roundId;

  @override
  bool operator ==(Object other) =>
      other is CouncilRoundKey &&
      other.councilName == councilName &&
      other.roundId == roundId;

  @override
  int get hashCode => Object.hash(councilName, roundId);
}

final councilRoundProvider = FutureProvider.family<Map<String, dynamic>,
    CouncilRoundKey>((ref, key) async {
  return ref
      .watch(dashboardApiProvider)
      .councilRound(key.councilName, key.roundId);
});

final councilRoundOneRoundCommandProvider = FutureProvider.family<
    Map<String, dynamic>, CouncilRoundKey>((ref, key) async {
  return ref
      .watch(dashboardApiProvider)
      .councilRoundOneRoundCommand(key.councilName, key.roundId);
});

/// Family key keyed by (council, resource name).
class CouncilResourceKey {
  const CouncilResourceKey(this.councilName, this.resourceName);
  final String councilName;
  final String resourceName;

  @override
  bool operator ==(Object other) =>
      other is CouncilResourceKey &&
      other.councilName == councilName &&
      other.resourceName == resourceName;

  @override
  int get hashCode => Object.hash(councilName, resourceName);
}

final councilResourceProvider = FutureProvider.family<Map<String, dynamic>,
    CouncilResourceKey>((ref, key) async {
  return ref
      .watch(dashboardApiProvider)
      .councilResource(key.councilName, key.resourceName);
});

class CouncilNodeKey {
  const CouncilNodeKey(this.councilName, this.nodeId);
  final String councilName;
  final String nodeId;

  @override
  bool operator ==(Object other) =>
      other is CouncilNodeKey &&
      other.councilName == councilName &&
      other.nodeId == nodeId;

  @override
  int get hashCode => Object.hash(councilName, nodeId);
}

final councilNodeSourceProvider = FutureProvider.family<Map<String, dynamic>,
    CouncilNodeKey>((ref, key) async {
  return ref
      .watch(dashboardApiProvider)
      .councilNodeSource(key.councilName, key.nodeId);
});

// ── Scaffold (kind-driven panels) ─────────────────────────────────

class ScaffoldLayoutKey {
  const ScaffoldLayoutKey(this.councilName, this.page);
  final String councilName;
  final String page;
  @override
  bool operator ==(Object other) =>
      other is ScaffoldLayoutKey &&
      other.councilName == councilName &&
      other.page == page;
  @override
  int get hashCode => Object.hash(councilName, page);
}

class ScaffoldSlotKey {
  const ScaffoldSlotKey({
    required this.councilName,
    required this.page,
    required this.slotId,
    this.overrides = const {},
  });
  final String councilName;
  final String page;
  final String slotId;
  final Map<String, dynamic> overrides;

  @override
  bool operator ==(Object other) =>
      other is ScaffoldSlotKey &&
      other.councilName == councilName &&
      other.page == page &&
      other.slotId == slotId &&
      _mapEq(other.overrides, overrides);
  @override
  int get hashCode => Object.hash(
        councilName,
        page,
        slotId,
        Object.hashAllUnordered(
          overrides.entries.map((e) => Object.hash(e.key, e.value)),
        ),
      );

  static bool _mapEq(Map<String, dynamic> a, Map<String, dynamic> b) {
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if (b[e.key] != e.value) return false;
    }
    return true;
  }
}

final scaffoldLayoutProvider = FutureProvider.family<Map<String, dynamic>,
    ScaffoldLayoutKey>((ref, k) async {
  return ref.watch(dashboardApiProvider).councilScaffoldLayout(
        k.councilName,
        page: k.page,
      );
});

final scaffoldSlotProvider = FutureProvider.family<Map<String, dynamic>,
    ScaffoldSlotKey>((ref, k) async {
  return ref.watch(dashboardApiProvider).councilScaffoldSlot(
        k.councilName,
        slotId: k.slotId,
        page: k.page,
        overrides: k.overrides,
      );
});
