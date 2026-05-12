import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/providers.dart';
import 'error_view.dart';

/// Inline panel embedded in the run-page sidebar for editing the
/// manifest knobs + ``.launch.json`` and launching the council.
///
/// Each seat shows only the knobs that matter to it. The factory and
/// cwd are constants of this codebase (always
/// ``ml_trainer.council.factory:build`` against the ml-trainer repo)
/// and are baked into the cmd we write — not exposed as form fields.
class LaunchConfigPanel extends ConsumerStatefulWidget {
  const LaunchConfigPanel({
    super.key,
    required this.councilName,
    this.running = false,
  });

  final String councilName;
  final bool running;

  @override
  ConsumerState<LaunchConfigPanel> createState() => _LaunchConfigPanelState();
}

/// The single count-knob each seat exposes, plus its display label.
/// Seats not listed here render no fields at all.
class _SeatSpec {
  const _SeatSpec(this.label, this.countKnob);
  final String label;
  final String? countKnob; // null = only `model` is editable.
}

const Map<String, _SeatSpec> _seats = {
  'empirical_analyst': _SeatSpec('Empirical Analyst', 'n_candidates'),
  'theoretical_analyst': _SeatSpec('Theoretical Analyst', 'n_candidates'),
  'oob_analyst': _SeatSpec('OOB Analyst', 'n_candidates'),
  'decider': _SeatSpec('Decider', 'max_promotions'),
};

const String _factory = 'ml_trainer.council.factory:build';

class _LaunchConfigPanelState extends ConsumerState<LaunchConfigPanel> {
  final _maxRoundsCtrl = TextEditingController(text: '30');
  final _maxCriticTurnsCtrl = TextEditingController(text: '2');
  bool _costCapActive = false;

  Map<String, dynamic>? _manifest;
  final Map<String, TextEditingController> _countCtrls = {};
  final Map<String, TextEditingController> _modelCtrls = {};

  /// Working directory for the launch (ml-trainer repo path, from /health).
  String? _cwd;

  /// Absolute path to scripts/launch_council.py in the dashboard repo.
  /// Resolved from /health so the wrapper is found regardless of cwd.
  String? _scriptPath;

  /// Canonical session dir (= --runs-root), captured from the
  /// /launch-config GET response.
  String? _sessionPath;

  bool _loading = true;
  String? _loadError;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  @override
  void dispose() {
    _maxRoundsCtrl.dispose();
    _maxCriticTurnsCtrl.dispose();
    for (final c in _countCtrls.values) {
      c.dispose();
    }
    for (final c in _modelCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadInitial() async {
    final api = ref.read(dashboardApiProvider);
    try {
      final results = await Future.wait([
        api.health(),
        api.council(widget.councilName),
        api.councilLaunchConfig(widget.councilName),
      ]);
      final health = results[0];
      final council = results[1];
      final launch = results[2];

      _cwd = health['ml_trainer_repo'] as String?;
      final dashboardRepo = health['dashboard_repo'] as String?;
      if (dashboardRepo != null) {
        _scriptPath = '$dashboardRepo/scripts/launch_council.py';
      }

      final launchPath = launch['path'] as String?;
      if (launchPath != null) {
        final slash = launchPath.lastIndexOf('/');
        if (slash > 0) _sessionPath = launchPath.substring(0, slash);
      }

      if (launch['exists'] == true) {
        _applyExistingLaunch(launch['config'] as Map<String, dynamic>);
      }

      _manifest = Map<String, dynamic>.from(council['manifest'] as Map);
      for (final raw in (_manifest!['agents'] as List).cast<Map>()) {
        final a = Map<String, dynamic>.from(raw);
        final id = a['id'] as String;
        final seat = _seats[id];
        if (seat == null) continue;
        if (seat.countKnob != null) {
          _countCtrls[id] = TextEditingController(
              text: (a[seat.countKnob] ?? '').toString());
        }
        _modelCtrls[id] = TextEditingController(
            text: (a['model'] ?? 'sonnet').toString());
      }

      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _loadError = e.toString();
        _loading = false;
      });
    }
  }

  /// Recover form state from a previously-saved ``.launch.json``.
  /// Best-effort: cmd is parsed for the flags emitted by [_buildCmd].
  void _applyExistingLaunch(Map<String, dynamic> cfg) {
    final cmd = (cfg['cmd'] as List?)?.cast<String>() ?? const [];
    for (var i = 0; i < cmd.length - 1; i++) {
      switch (cmd[i]) {
        case '--max-rounds':
          _maxRoundsCtrl.text = cmd[i + 1];
        case '--max-critic-turns':
          _maxCriticTurnsCtrl.text = cmd[i + 1];
      }
    }
    _costCapActive = cmd.contains('--cost-cap-active');
  }

  List<String> _buildCmd() {
    final cmd = <String>[
      'uv',
      'run',
      'python',
      _scriptPath ?? 'scripts/launch_council.py',
      '--runs-root',
      _sessionPath ?? '',
      '--factory',
      _factory,
      '--max-rounds',
      _maxRoundsCtrl.text.trim(),
      '--max-critic-turns',
      _maxCriticTurnsCtrl.text.trim(),
    ];
    if (_costCapActive) cmd.add('--cost-cap-active');
    return cmd;
  }

  /// Apply the per-seat knobs (count + model) back onto the manifest.
  /// Empty count fields drop the key (= inherit manifest default).
  Map<String, dynamic> _buildManifestWithKnobs() {
    final base = Map<String, dynamic>.from(_manifest!);
    final agents = (base['agents'] as List)
        .map((a) => Map<String, dynamic>.from(a as Map))
        .toList();
    for (var i = 0; i < agents.length; i++) {
      final a = agents[i];
      final id = a['id'] as String;
      final seat = _seats[id];
      if (seat == null) continue;
      if (seat.countKnob != null) {
        final t = _countCtrls[id]?.text.trim() ?? '';
        if (t.isEmpty) {
          a.remove(seat.countKnob);
        } else {
          final v = int.tryParse(t);
          if (v != null) a[seat.countKnob!] = v;
        }
      }
      final model = _modelCtrls[id]?.text.trim();
      if (model != null && model.isNotEmpty) a['model'] = model;
    }
    base['agents'] = agents;
    return base;
  }

  Future<void> _saveAndStart() async {
    setState(() => _saving = true);
    final api = ref.read(dashboardApiProvider);
    try {
      await api.putCouncil(widget.councilName, _buildManifestWithKnobs());
      ref.invalidate(councilProvider(widget.councilName));

      await api.setCouncilLaunchConfig(
        widget.councilName,
        cmd: _buildCmd(),
        cwd: _cwd,
      );

      await api.councilClearStop(widget.councilName);
      await api.councilStart(widget.councilName);

      ref.invalidate(councilSessionProvider(widget.councilName));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Council launched.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Launch failed: $e')),
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
        padding: EdgeInsets.symmetric(vertical: 24),
        child: LoadingView(label: 'Loading config…'),
      );
    }
    if (_loadError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: ErrorView(_loadError!),
      );
    }
    final locked = widget.running;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final id in _seats.keys)
            if (_modelCtrls.containsKey(id)) _seatBlock(id, locked),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                  child: _intField(_maxRoundsCtrl, 'Max rounds',
                      enabled: !locked)),
              const SizedBox(width: 8),
              Expanded(
                  child: _intField(_maxCriticTurnsCtrl, 'Max critic turns',
                      enabled: !locked)),
            ],
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Cost cap active'),
            value: _costCapActive,
            onChanged: locked ? null : (v) => setState(() => _costCapActive = v),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: (_saving || locked) ? null : _saveAndStart,
            icon: _saving
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.play_arrow),
            label: Text(locked ? 'Running…' : 'Save & Start'),
          ),
        ],
      ),
    );
  }

  Widget _seatBlock(String id, bool locked) {
    final seat = _seats[id]!;
    final countCtrl = _countCtrls[id];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(seat.label,
                style: Theme.of(context).textTheme.titleSmall),
          ),
          Row(
            children: [
              if (countCtrl != null) ...[
                Expanded(
                    child: _intField(countCtrl, seat.countKnob!,
                        enabled: !locked)),
                const SizedBox(width: 8),
              ],
              Expanded(child: _modelField(_modelCtrls[id]!, enabled: !locked)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _modelField(TextEditingController ctrl, {bool enabled = true}) =>
      TextField(
        controller: ctrl,
        enabled: enabled,
        decoration: const InputDecoration(
          labelText: 'model',
          border: OutlineInputBorder(),
          isDense: true,
        ),
      );

  Widget _intField(TextEditingController ctrl, String label,
          {bool enabled = true}) =>
      TextField(
        controller: ctrl,
        enabled: enabled,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      );
}
