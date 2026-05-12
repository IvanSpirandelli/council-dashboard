import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'pages/council_builder_page.dart';
import 'pages/council_home_page.dart';
import 'pages/council_run_page.dart';
import 'pages/home_page.dart';
import 'pages/performance_page.dart';
import 'pages/round_page.dart';

void main() {
  runApp(const ProviderScope(child: CouncilDashboardApp()));
}

final _router = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (_, __) => const HomePage()),
    GoRoute(
      path: '/councils/:name',
      builder: (_, state) =>
          CouncilHomePage(councilName: state.pathParameters['name']!),
    ),
    GoRoute(
      path: '/councils/:name/edit',
      builder: (_, state) => CouncilBuilderPage(
        councilName: state.pathParameters['name']!,
        initialAgentId: state.uri.queryParameters['agent'],
      ),
    ),
    GoRoute(
      path: '/councils/:name/run',
      builder: (_, state) =>
          CouncilRunPage(councilName: state.pathParameters['name']!),
    ),
    GoRoute(
      path: '/councils/:name/rounds/:round',
      builder: (_, state) => RoundPage(
        councilName: state.pathParameters['name']!,
        roundId: state.pathParameters['round']!,
      ),
    ),
    GoRoute(
      path: '/councils/:name/performance',
      builder: (_, state) =>
          PerformancePage(councilName: state.pathParameters['name']!),
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
