import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/providers.dart';
import '../widgets/error_view.dart';

/// Home page — one tile per council.
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final councils = ref.watch(councilsProvider);
    final health = ref.watch(healthProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Councils'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(councilsProvider);
              ref.invalidate(healthProvider);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          health.when(
            data: (h) => _HealthBar(data: h),
            error: (e, _) => ListTile(
              dense: true,
              leading: Icon(Icons.cloud_off,
                  color: Theme.of(context).colorScheme.error),
              title: Text('Backend unreachable: $e'),
            ),
            loading: () => const LinearProgressIndicator(minHeight: 2),
          ),
          Expanded(
            child: councils.when(
              loading: () => const LoadingView(label: 'Loading councils…'),
              error: (e, _) => ErrorView(e,
                  onRetry: () => ref.invalidate(councilsProvider)),
              data: (rows) => rows.isEmpty
                  ? const Center(
                      child: Text('No councils found under COUNCILS_ROOT.'))
                  : GridView.extent(
                      maxCrossAxisExtent: 360,
                      childAspectRatio: 1.4,
                      padding: const EdgeInsets.all(16),
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                      children: [
                        for (final c in rows) _CouncilTile(council: c),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CouncilTile extends StatelessWidget {
  const _CouncilTile({required this.council});
  final Map<String, dynamic> council;

  @override
  Widget build(BuildContext context) {
    final name = council['name'] as String;
    final desc = council['description'] as String? ?? '';
    final agents =
        ((council['agent_ids'] as List?) ?? const []).cast<String>();
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/councils/$name'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.account_tree_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(name,
                      style: Theme.of(context).textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis),
                ),
              ]),
              const SizedBox(height: 8),
              Expanded(
                child: Text(desc,
                    style: Theme.of(context).textTheme.bodyMedium,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis),
              ),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final a in agents.take(5))
                    Chip(
                      label: Text(a),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                    ),
                ],
              ),
            ],
          ),
        ),
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
