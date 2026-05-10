import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/providers.dart';
import '../widgets/error_view.dart';

class SessionsPage extends ConsumerWidget {
  const SessionsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(sessionsProvider);
    final health = ref.watch(healthProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Council sessions'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(sessionsProvider);
              ref.invalidate(healthProvider);
            },
          ),
          IconButton(
            tooltip: 'Performance table',
            icon: const Icon(Icons.table_chart_outlined),
            onPressed: () => context.push('/performance'),
          ),
        ],
      ),
      body: Column(
        children: [
          health.when(
            data: (h) => _HealthBar(data: h),
            error: (e, _) => ListTile(
              dense: true,
              leading: Icon(Icons.cloud_off, color: Theme.of(context).colorScheme.error),
              title: Text('Backend unreachable: $e'),
            ),
            loading: () => const LinearProgressIndicator(minHeight: 2),
          ),
          Expanded(
            child: sessions.when(
              data: (rows) => rows.isEmpty
                  ? const Center(child: Text('No sessions found under runs_root.'))
                  : ListView.separated(
                      itemCount: rows.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final s = rows[i];
                        final running = (s['runner']?['alive'] ?? false) as bool;
                        return ListTile(
                          leading: Icon(running
                              ? Icons.play_circle
                              : Icons.history_edu_outlined),
                          title: Text(s['id'] as String),
                          subtitle: Text(
                              '${s['round_count']} rounds · last modified ${s['modified_at']}'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => context.push('/sessions/${s['id']}'),
                        );
                      },
                    ),
              error: (e, _) =>
                  ErrorView(e, onRetry: () => ref.invalidate(sessionsProvider)),
              loading: () => const LoadingView(label: 'Loading sessions…'),
            ),
          ),
        ],
      ),
    );
  }
}

class _HealthBar extends StatelessWidget {
  const _HealthBar({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final ok = data['runs_root_exists'] == true;
    final color = ok
        ? Theme.of(context).colorScheme.tertiaryContainer
        : Theme.of(context).colorScheme.errorContainer;
    return Container(
      width: double.infinity,
      color: color,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        ok
            ? 'runs_root: ${data['runs_root']}'
            : 'runs_root MISSING: ${data['runs_root']}',
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}
