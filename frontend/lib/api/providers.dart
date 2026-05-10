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

final topologyProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  return ref.watch(dashboardApiProvider).topology();
});

final sessionsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  return ref.watch(dashboardApiProvider).sessions();
});

final sessionProvider = FutureProvider.family<Map<String, dynamic>, String>(
  (ref, sessionId) async {
    return ref.watch(dashboardApiProvider).session(sessionId);
  },
);

class RoundKey {
  const RoundKey(this.sessionId, this.roundId);
  final String sessionId;
  final String roundId;

  @override
  bool operator ==(Object other) =>
      other is RoundKey &&
      other.sessionId == sessionId &&
      other.roundId == roundId;

  @override
  int get hashCode => Object.hash(sessionId, roundId);
}

final roundProvider =
    FutureProvider.family<Map<String, dynamic>, RoundKey>((ref, key) async {
  return ref.watch(dashboardApiProvider).round(key.sessionId, key.roundId);
});

class PerfQuery {
  const PerfQuery({
    this.session,
    this.roundId,
    this.sort = 'cl2',
    this.asc = false,
    this.allVariants = false,
  });
  final String? session;
  final String? roundId;
  final String sort;
  final bool asc;
  final bool allVariants;

  @override
  bool operator ==(Object other) =>
      other is PerfQuery &&
      other.session == session &&
      other.roundId == roundId &&
      other.sort == sort &&
      other.asc == asc &&
      other.allVariants == allVariants;

  @override
  int get hashCode => Object.hash(session, roundId, sort, asc, allVariants);
}

final performanceProvider =
    FutureProvider.family<Map<String, dynamic>, PerfQuery>((ref, q) async {
  return ref.watch(dashboardApiProvider).performanceTable(
        session: q.session,
        roundId: q.roundId,
        sort: q.sort,
        asc: q.asc,
        allVariants: q.allVariants,
      );
});
