import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../models/coach_voice.dart';
import 'settings_service.dart';

// flutter_tts rate: 0.0 slowest, 1.0 fastest, 0.5 = Android's normal speed.
// A little slower than normal, so short cues are clear during exercise.
const double cueSpeechRate = 0.35;

// Speaks cues with flutter_tts. On Android a new cue interrupts one still
// being spoken (QUEUE_FLUSH, the plugin's default), so the newest is heard.
class CueSpeaker {
  final _tts = FlutterTts();
  final _sinceSpeak = Stopwatch(); // speak() call to the start of the audio
  bool _mandarin = false; // speak mandarinCues instead of the English text

  /// Installed English voices for the Settings picker, as {name, locale}.
  static Future<List<Map<String, String>>> englishVoices() async {
    final all = await FlutterTts().getVoices as List? ?? [];
    return [
      for (final v in all.cast<Map>())
        if ('${v['locale']}'.startsWith('en'))
          {'name': '${v['name']}', 'locale': '${v['locale']}'},
    ];
  }

  Future<void> init() async {
    // Member B: the Coach voice setting. Falls back to English when the
    // phone has no voice for the chosen language.
    final voice = await SettingsService.loadCoachVoice();
    final available = await _tts.isLanguageAvailable(voice.locale) == true;
    debugPrint('TTS ${voice.locale} available: $available');
    await _tts.setLanguage(available ? voice.locale : 'en-US');
    _mandarin = available && voice == CoachVoice.mandarin;
    final picked = await SettingsService.loadEnglishVoice();
    if (voice == CoachVoice.english && picked != null) {
      await _tts.setVoice({'name': picked.name, 'locale': picked.locale});
    }
    await _tts.setSpeechRate(cueSpeechRate);
    _tts.setStartHandler(() {
      if (!_sinceSpeak.isRunning) return;
      debugPrint(
        'CUE audio started ${_sinceSpeak.elapsedMilliseconds} ms after speak()',
      );
      _sinceSpeak
        ..stop()
        ..reset();
    });
  }

  Future<void> speak(String text) async {
    _sinceSpeak
      ..reset()
      ..start();
    await _tts.speak(_mandarin ? mandarinCues[text] ?? text : text);
  }

  Future<void> stop() async {
    await _tts.stop();
  }
}
