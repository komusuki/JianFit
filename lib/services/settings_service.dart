import 'package:shared_preferences/shared_preferences.dart';

import '../models/strictness.dart';

// Saved app settings (roadmap Part 10: strictness level, voice on or off).
class SettingsService {
  static const _strictnessKey = 'strictness';
  static const _voiceKey = 'voice_on';
  static final _prefs = SharedPreferencesAsync();

  static Future<Strictness> loadStrictness() async {
    final name = await _prefs.getString(_strictnessKey);
    return Strictness.values.firstWhere(
          (s) => s.name == name,
      orElse: () => Strictness.standard,
    );
  }

  static Future<void> saveStrictness(Strictness s) =>
      _prefs.setString(_strictnessKey, s.name);

  static Future<bool> loadVoiceOn() async =>
      await _prefs.getBool(_voiceKey) ?? true;

  static Future<void> saveVoiceOn(bool on) => _prefs.setBool(_voiceKey, on);
}