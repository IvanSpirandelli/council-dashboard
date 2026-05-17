import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../api/providers.dart';
import '../scaffold/page_shells.dart';

/// Per-council home: scaffold "top" page on the left, action tiles
/// (edit-council, continue-tasks) on the right.
///
/// Action tiles stay bespoke because they're not data panels (they
/// edit manifests and start subprocesses). Everything else comes from
/// the kind's registered panels via `PanelStackView`.
class CouncilHomePage extends ConsumerStatefulWidget {
  const CouncilHomePage({super.key, required this.councilName});

  final String councilName;

  @override
  ConsumerState<CouncilHomePage> createState() => _CouncilHomePageState();
}

class _CouncilHomePageState extends ConsumerState<CouncilHomePage> {
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted) return;
      ref.invalidate(councilSessionProvider(widget.councilName));
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(councilSessionProvider(widget.councilName));
    final layoutKey = ScaffoldLayoutKey(widget.councilName, 'top');

    final perfTile = Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                icon: const Icon(Icons.open_in_new),
                label: const Text('Full table'),
                onPressed: () => context
                    .push('/councils/${widget.councilName}/performance'),
              ),
            ),
          ),
          Expanded(
            child: PanelStackView(
              councilName: widget.councilName,
              page: 'top',
            ),
          ),
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.councilName),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(scaffoldLayoutProvider(layoutKey));
              ref.invalidate(councilSessionProvider(widget.councilName));
            },
          ),
        ],
      ),
      body: LayoutBuilder(builder: (ctx, c) {
        final wide = c.maxWidth > 900;
        final actionTiles = _ActionTiles(
          councilName: widget.councilName,
          session: session,
        );
        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 3, child: perfTile),
              Expanded(flex: 2, child: actionTiles),
            ],
          );
        }
        return ListView(
          children: [
            SizedBox(height: 420, child: perfTile),
            actionTiles,
          ],
        );
      }),
    );
  }
}

class _ActionTiles extends StatelessWidget {
  const _ActionTiles({required this.councilName, required this.session});
  final String councilName;
  final AsyncValue<Map<String, dynamic>> session;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ActionCard(
            icon: Icons.edit_note,
            title: 'Edit council',
            subtitle:
                'Manifest, prompts, resources, agent topology, preview.',
            onTap: () => context.push('/councils/$councilName/edit'),
          ),
          const SizedBox(height: 12),
          _ContinueTasksCard(councilName: councilName, session: session),
        ],
      ),
    );
  }
}

class _ContinueTasksCard extends StatelessWidget {
  const _ContinueTasksCard({
    required this.councilName,
    required this.session,
  });
  final String councilName;
  final AsyncValue<Map<String, dynamic>> session;

  @override
  Widget build(BuildContext context) {
    return session.when(
      loading: () => const _ActionCard(
        icon: Icons.hourglass_top,
        title: 'Continue tasks',
        subtitle: 'Loading session state…',
      ),
      error: (e, _) => _ActionCard(
        icon: Icons.error_outline,
        title: 'Continue tasks',
        subtitle: 'Backend error: $e',
      ),
      data: (s) {
        final runner = s['runner'] as Map<String, dynamic>?;
        final running = (runner?['alive'] ?? false) as bool;
        final stopPending = s['stop_pending'] == true;
        final rounds = (s['rounds'] as List?)?.length ?? 0;
        final subtitle = StringBuffer()
          ..write(running ? 'Running' : 'Idle')
          ..write(' · $rounds round${rounds == 1 ? '' : 's'}');
        if (stopPending) subtitle.write(' · stop pending');
        return _ActionCard(
          icon: running ? Icons.play_circle : Icons.play_arrow,
          title: 'Continue tasks',
          subtitle: subtitle.toString(),
          onTap: () => context.push('/councils/$councilName/run'),
        );
      },
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(icon, size: 32),
        title:
            Text(title, style: Theme.of(context).textTheme.titleMedium),
        subtitle: Text(subtitle),
        trailing:
            onTap != null ? const Icon(Icons.chevron_right) : null,
        onTap: onTap,
      ),
    );
  }
}
