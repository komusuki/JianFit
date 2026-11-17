import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

// flutter_tts rate: 0.0 slowest, 1.0 fastest, 0.5 = Android's normal speed.
// A little slower than normal, so short cues are clear during exercise.
const double cueSpeechRate = 0.35;

// Speaks cues with flutter_tts. On Android a new cue interrupts one still
// being spoken (QUEUE_FLUSH, the plugin's default), so the newest is heard.
class CueSpeaker {
  final _tts = FlutterTts();

  Future<void> init() async {
    final available = await _tts.isLanguageAvailable('en-US');
    debugPrint('TTS en-US available: $available');
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(cueSpeechRate);
  }

  Future<void> speak(String text) async {
    await _tts.speak(text);
  }

  Future<void> stop() async {
    await _tts.stop();
  }
}
