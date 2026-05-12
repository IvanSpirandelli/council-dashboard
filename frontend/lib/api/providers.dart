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

class PerfQuery {
  const PerfQuery({
    required this.councilName,
    this.sort = 'test_pearson_r_mean',
    this.ascending = false,
    this.limit,
  });
  final String councilName;
  final String sort;
  final bool ascending;
  final int? limit;

  @override
  bool operator ==(Object other) =>
      other is PerfQuery &&
      other.councilName == councilName &&
      other.sort == sort &&
      other.ascending == ascending &&
      other.limit == limit;

  @override
  int get hashCode => Object.hash(councilName, sort, ascending, limit);
}

final councilPerformanceProvider =
    FutureProvider.family<Map<String, dynamic>, PerfQuery>((ref, q) async {
  return ref.watch(dashboardApiProvider).councilPerformance(
        q.councilName,
        sort: q.sort,
        ascending: q.ascending,
        limit: q.limit,
      );
});
