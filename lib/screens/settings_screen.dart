import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/app_palette.dart';
import '../models/strictness.dart';
import '../services/settings_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Strictness _strictness = Strictness.standard;
  bool _voiceOn = true;
  bool _replay = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final strictness = await SettingsService.loadStrictness();
    final voiceOn = await SettingsService.loadVoiceOn();
    final replay = await SettingsService.loadReplayMode();
    if (!mounted) return;
    setState(() {
      _strictness = strictness;
      _voiceOn = voiceOn;
      _replay = replay;
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Default strictness',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                const Text(
                  'How clean each rep must be. Safety checks are the same at every level.',
                ),
                const SizedBox(height: 8),
                SegmentedButton<Strictness>(
                  segments: const [
                    ButtonSegment(
                      value: Strictness.beginner,
                      label: Text('Beginner'),
                    ),
                    ButtonSegment(
                      value: Strictness.standard,
                      label: Text('Standard'),
                    ),
                    ButtonSegment(
                      value: Strictness.strict,
                      label: Text('Strict'),
                    ),
                  ],
                  selected: {_strictness},
                  onSelectionChanged: (s) {
                    setState(() => _strictness = s.first);
                    SettingsService.saveStrictness(s.first);
                  },
                ),
                const SizedBox(height: 24),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Voice cues'),
                  subtitle: const Text(
                    'Coach Zhang speaks corrections out loud',
                  ),
                  value: _voiceOn,
                  onChanged: (v) {
                    setState(() => _voiceOn = v);
                    SettingsService.saveVoiceOn(v);
                  },
                ),
                const SizedBox(height: 24),
                Text('Colors', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                for (final p in AppPalette.values)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: _swatches(p),
                    title: Text(p.label),
                    selected: p == SettingsService.palette.value,
                    trailing: p == SettingsService.palette.value
                        ? const Icon(Icons.check_circle)
                        : null,
                    onTap: () => SettingsService.savePalette(p),
                  ),
                // Hidden in release builds: only debug builds show it.
                if (kDebugMode) ...[
                  const SizedBox(height: 24),
                  Text(
                    'Developer',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Replay mode'),
                    subtitle: const Text(
                      'Single Exercise plays a recorded clip from '
                      'assets/replays/ instead of the camera',
                    ),
                    value: _replay,
                    onChanged: (v) {
                      setState(() => _replay = v);
                      SettingsService.saveReplayMode(v);
                    },
                  ),
                ],
              ],
            ),
    );
  }

  // Two dots showing a color set's main and highlight colors.
  Widget _swatches(AppPalette p) => ExcludeSemantics(
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final c in [p.fill, p.highlight])
          Container(
            width: 24,
            height: 24,
            margin: const EdgeInsets.only(right: 4),
            decoration: BoxDecoration(
              color: c,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.black26),
            ),
          ),
      ],
    ),
  );
}
