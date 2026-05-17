/// Page shells + the reusable panel-stack view.
///
/// `PanelStackView` is the work unit: fetch a layout, render each slot
/// via the kind registry. Three shells wrap it for the three scaffold
/// pages; the home page also reuses `PanelStackView` directly so its
/// side-by-side perf-preview + actions layout shares the same fetch
/// path.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/providers.dart';
import '../widgets/error_view.dart';
import 'kind_registry.dart';
import 'panel.dart';

/// Layout-fetch + slot render for one scaffold page. Wrap in your own
/// Scaffold/AppBar if you need a full page; embed directly to compose
/// alongside other widgets.
class PanelStackView extends ConsumerWidget {
  const PanelStackView({super.key, required this.councilName, required this.page});

  final String councilName;
  final String page;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layoutKey = ScaffoldLayoutKey(councilName, page);
    final layout = ref.watch(scaffoldLayoutProvider(layoutKey));
    return layout.when(
      loading: () => const LoadingView(label: 'Loading…'),
      error: (e, _) => ErrorView(e,
          onRetry: () => ref.invalidate(scaffoldLayoutProvider(layoutKey))),
      data: (data) {
        final kind = data['kind'] as String?;
        final slots = ((data['slots'] as List?) ?? [])
            .cast<Map<String, dynamic>>()
            .map(PanelSpec.fromJson)
            .toList();
        if (slots.isEmpty) {
          return Center(child: Text('No panels declared on page "$page".'));
        }
        return ListView(
          children: [
            for (final s in slots)
              SlotView(
                councilName: councilName,
                page: page,
                spec: s,
                kind: kind,
              ),
          ],
        );
      },
    );
  }
}

class SlotView extends ConsumerWidget {
  const SlotView({
    super.key,
    required this.councilName,
    required this.page,
    required this.spec,
    required this.kind,
  });

  final String councilName;
  final String page;
  final PanelSpec spec;
  final String? kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = ScaffoldSlotKey(
      councilName: councilName,
      page: page,
      slotId: spec.slotId,
    );
    final slot = ref.watch(scaffoldSlotProvider(key));
    return slot.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => ErrorView(e,
          onRetry: () => ref.invalidate(scaffoldSlotProvider(key))),
      data: (data) {
        final resp = PanelResponse.fromJson(data);
        final builder = resolvePanel(resp.panelId, kind: kind);
        return (builder ?? unknownPanel)(resp);
      },
    );
  }
}

class _ShellBase extends ConsumerWidget {
  const _ShellBase({
    required this.councilName,
    required this.page,
    required this.appBarTitle,
  });

  final String councilName;
  final String page;
  final String appBarTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layoutKey = ScaffoldLayoutKey(councilName, page);
    return Scaffold(
      appBar: AppBar(
        title: Text(appBarTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(scaffoldLayoutProvider(layoutKey)),
          ),
        ],
      ),
      body: PanelStackView(councilName: councilName, page: page),
    );
  }
}

class TopResultsShell extends StatelessWidget {
  const TopResultsShell({super.key, required this.councilName});
  final String councilName;
  @override
  Widget build(BuildContext context) => _ShellBase(
        councilName: councilName,
        page: 'top',
        appBarTitle: councilName,
      );
}

class FullResultsShell extends StatelessWidget {
  const FullResultsShell({super.key, required this.councilName});
  final String councilName;
  @override
  Widget build(BuildContext context) => _ShellBase(
        councilName: councilName,
        page: 'full',
        appBarTitle: '$councilName — full results',
      );
}

class InfoShell extends StatelessWidget {
  const InfoShell({super.key, required this.councilName});
  final String councilName;
  @override
  Widget build(BuildContext context) => _ShellBase(
        councilName: councilName,
        page: 'info',
        appBarTitle: '$councilName — info',
      );
}
