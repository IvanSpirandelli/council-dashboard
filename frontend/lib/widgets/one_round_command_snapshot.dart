import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/providers.dart';

/// Read-only view of the one-round command that was pinned to a given
/// round at start. Empty if the round committed without an active
/// human directive.
class OneRoundCommandSnapshot extends ConsumerWidget {
  const OneRoundCommandSnapshot({
    super.key,
    required this.councilName,
    required this.roundId,
  });

  final String councilName;
  final String roundId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snap = ref.watch(councilRoundOneRoundCommandProvider(
        CouncilRoundKey(councilName, roundId)));
    return snap.when(
      loading: () => const SizedBox.shrink(),
      error: (e, _) {
        debugPrint('one-round command snapshot load failed: $e');
        return const SizedBox.shrink();
      },
      data: (data) {
        final body = ((data['body'] as String?) ?? '').trim();
        if (body.isEmpty) return const SizedBox.shrink();
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.flag_outlined, size: 16),
                    const SizedBox(width: 6),
                    Text('One-round command — injected at round start',
                        style: Theme.of(context).textTheme.labelLarge),
                  ],
                ),
                const SizedBox(height: 6),
                SelectableText(
                  body,
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
