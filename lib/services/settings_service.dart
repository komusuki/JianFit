import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_palette.dart';
import '../models/coach_voice.dart';
import '../models/strictness.dart';

// Saved app settings (roadmap Part 10: strictness level, voice on or off).
class SettingsService {
  static const _strictnessKey = 'strictness';
  static const _voiceKey = 'voice_on';
  static const _replayKey = 'replay_mode';
  static const _paletteKey = 'palette';
  static const _lastRoutineKey = 'last_routine_id';
  static const _coachVoiceKey = 'coach_voice';
  static const _voiceNameKey = 'voice_name';
  static const _voiceLocaleKey = 'voice_locale';
  static final _prefs = SharedPreferencesAsync();

  /// The color set in use. main() loads it at startup; the app rebuilds its
  /// theme whenever it changes.
  static final palette = ValueNotifier<AppPalette>(AppPalette.greenYellow);

  static Future<AppPalette> loadPalette() async {
    final name = await _prefs.getString(_paletteKey);
    return AppPalette.values.firstWhere(
      (p) => p.name == name,
      orElse: () => AppPalette.greenYellow,
    );
  }

  static Future<void> savePalette(AppPalette p) {
    palette.value = p;
    return _prefs.setString(_paletteKey, p.name);
  }

  static Future<Strictness> loadStrictness() async {
    final name = await _prefs.getString(_strictnessKey);
    return Strictness.values.firstWhere(
      (s) => s.name == name,
      orElse: () => Strictness.standard,
    );
  }

  static Future<void> saveStrictness(Strictness s) =>
      _prefs.setString(_strictnessKey, s.name);

  /// The routine Today shows: the one started most recently.
  static Future<int?> loadLastRoutineId() => _prefs.getInt(_lastRoutineKey);

  static Future<void> saveLastRoutineId(int id) =>
      _prefs.setInt(_lastRoutineKey, id);

  static Future<bool> loadVoiceOn() async =>
      await _prefs.getBool(_voiceKey) ?? true;

  static Future<void> saveVoiceOn(bool on) => _prefs.setBool(_voiceKey, on);

  static Future<CoachVoice> loadCoachVoice() async {
    final name = await _prefs.getString(_coachVoiceKey);
    return CoachVoice.values.firstWhere(
      (v) => v.name == name,
      orElse: () => CoachVoice.english,
    );
  }

  static Future<void> saveCoachVoice(CoachVoice v) =>
      _prefs.setString(_coachVoiceKey, v.name);

  /// The installed English voice picked in Settings, or null for the phone's
  /// default. flutter_tts needs both the name and the locale.
  static Future<({String name, String locale})?> loadEnglishVoice() async {
    final name = await _prefs.getString(_voiceNameKey);
    final locale = await _prefs.getString(_voiceLocaleKey);
    if (name == null || locale == null) return null;
    return (name: name, locale: locale);
  }

  static Future<void> saveEnglishVoice(String name, String locale) async {
    await _prefs.setString(_voiceNameKey, name);
    await _prefs.setString(_voiceLocaleKey, locale);
  }

  /// Developer: Single Exercise plays a recorded clip from assets/replays/
  /// instead of the camera (Member C's replay mode).
  static Future<bool> loadReplayMode() async =>
      await _prefs.getBool(_replayKey) ?? false;

  static Future<void> saveReplayMode(bool on) => _prefs.setBool(_replayKey, on);
}
