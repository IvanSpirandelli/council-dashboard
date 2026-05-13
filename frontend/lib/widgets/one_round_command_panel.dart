import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/providers.dart';

/// Editor for the pending one-round command, embedded in the run-page
/// sidebar. The text gets injected into the next round as a top-priority
/// context block; the council loop snapshots it into the round dir and
/// clears the pending file so the next round starts blank.
class OneRoundCommandPanel extends ConsumerStatefulWidget {
  const OneRoundCommandPanel({super.key, required this.councilName});

  final String councilName;

  @override
  ConsumerState<OneRoundCommandPanel> createState() =>
      _OneRoundCommandPanelState();
}

class _OneRoundCommandPanelState extends ConsumerState<OneRoundCommandPanel> {
  static const _resourceName = 'one_round_command.md';
  static const _flagsResource = 'one_round_command.flags.json';

  final _ctrl = TextEditingController();
  String _loadedText = '';
  bool _clearAfterRound = false;
  bool _loadedClearAfterRound = false;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final api = ref.read(dashboardApiProvider);
    try {
      final r =
          await api.councilResource(widget.councilName, _resourceName);
      final body = (r['body'] as String?) ?? '';
      _loadedText = body;
      // Preserve in-flight unsaved edits if the user has typed since load.
      if (_ctrl.text.isEmpty) _ctrl.text = body;

      bool clearFlag = false;
      try {
        final flags =
            await api.councilResource(widget.councilName, _flagsResource);
        final flagBody = (flags['body'] as String?) ?? '';
        if (flagBody.trim().isNotEmpty) {
          final decoded = jsonDecode(flagBody);
          if (decoded is Map && decoded['clear_after_round'] == true) {
            clearFlag = true;
          }
        }
      } catch (_) {
        // Flag file missing or invalid → keep the carry-over default.
      }
      _loadedClearAfterRound = clearFlag;
      _clearAfterRound = clearFlag;

      setState(() {
        _loading = false;
        _error = null;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final api = ref.read(dashboardApiProvider);
    try {
      await api.putCouncilResource(
          widget.councilName, _resourceName, _ctrl.text);
      await api.putCouncilResource(
        widget.councilName,
        _flagsResource,
        jsonEncode({'clear_after_round': _clearAfterRound}),
      );
      _loadedText = _ctrl.text;
      _loadedClearAfterRound = _clearAfterRound;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('One-round command saved.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final pending = _loadedText.trim().isNotEmpty;
    final dirty = _ctrl.text != _loadedText ||
        _clearAfterRound != _loadedClearAfterRound;
    final pendingBlurb = pending
        ? (_loadedClearAfterRound
            ? 'Pending — injected into the next round, then cleared.'
            : 'Pending — carries over to every round until cleared.')
        : 'Empty — next round starts with no human directive.';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              'One-round command',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          Text(
            pendingBlurb,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Load error: $_error',
                  style: const TextStyle(color: Colors.red)),
            ),
          const SizedBox(height: 8),
          TextField(
            controller: _ctrl,
            minLines: 4,
            maxLines: 10,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText:
                  'Type a directive (e.g. "Focus on topological scalars."). It carries over until you clear it.',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Clear after round'),
            subtitle: const Text(
                'Pending file is emptied once the round finishes its LLM calls.'),
            value: _clearAfterRound,
            onChanged: _saving
                ? null
                : (v) => setState(() => _clearAfterRound = v),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: (!_saving && dirty) ? _save : null,
                  icon: _saving
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save),
                  label: Text(dirty ? 'Save' : 'Saved'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Reload from disk',
                onPressed: _saving ? null : _load,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
