import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

// flutter_tts rate: 0.0 slowest, 1.0 fastest, 0.5 = Android's normal speed.
// A little slower than normal, so short cues are clear during exercise.
const double cueSpeechRate = 0.35;

// Speaks cues with flutter_tts. On Android a new cue interrupts one still
// being spoken (QUEUE_FLUSH, the plugin's default), so the newest is heard.
class CueSpeaker {
  final _tts = FlutterTts();
  final _sinceSpeak = Stopwatch(); // speak() call to the start of the audio

  Future<void> init() async {
    final available = await _tts.isLanguageAvailable('en-US');
    debugPrint('TTS en-US available: $available');
    await _tts.setLanguage('en-US');
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
    await _tts.speak(text);
  }

  Future<void> stop() async {
    await _tts.stop();
  }
}
