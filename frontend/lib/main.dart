import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'pages/performance_page.dart';
import 'pages/round_page.dart';
import 'pages/session_page.dart';
import 'pages/sessions_page.dart';

void main() {
  runApp(const ProviderScope(child: CouncilDashboardApp()));
}

final _router = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (_, __) => const SessionsPage()),
    GoRoute(
      path: '/sessions/:id',
      builder: (_, state) =>
          SessionPage(sessionId: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/sessions/:id/rounds/:round',
      builder: (_, state) => RoundPage(
        sessionId: state.pathParameters['id']!,
        roundId: state.pathParameters['round']!,
      ),
    ),
    GoRoute(
      path: '/performance',
      builder: (_, state) =>
          PerformancePage(sessionFilter: state.uri.queryParameters['session']),
    ),
  ],
);

class CouncilDashboardApp extends StatelessWidget {
  const CouncilDashboardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Council Dashboard',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF3949AB),
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF7986CB),
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      routerConfig: _router,
    );
  }
}
