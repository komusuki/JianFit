// Cue manager (roadmap Part 7, Day 8): after each judged rep, decides which
// correction to show and whether to speak it.
//   One cue per rep: the verdict's top failed check (safety first).
//   The same cue is not spoken again within cueRepeatMs, except safety cues.
//   The same mistake tipAfterMistakes times in a set: report a tip card.
//   Voice off: show the cue, never speak it.
// Plain Dart (no Flutter), so `dart test` covers it.
// lib/services/cue_speaker.dart does the speaking.

import '../models/exercise_definition.dart';
import 'constants.dart';
import 'form_judge.dart';

/// What to do after one rep.
class CueDecision {
  const CueDecision({this.text, this.speak = false, this.tips = const []});

  /// The cue to show, or null to clear the banner (correct rep).
  final String? text;

  /// Speak [text] now.
  final bool speak;

  /// Checks that just failed for the tipAfterMistakes-th time in this set:
  /// show their tip card. Each check is reported once per set.
  final List<FormCheck> tips;
}

class CueManager {
  CueManager({this.voiceOn = true});

  /// The user's voice setting (SettingsService.loadVoiceOn()).
  bool voiceOn;

  final _lastSpokenMs = <String, int>{};
  final _mistakes = <String, int>{};

  /// Call once per judged rep, with the time the rep ended.
  CueDecision onRep(RepVerdict verdict, int tMs) {
    final tips = <FormCheck>[];
    for (final c in verdict.failed) {
      final n = (_mistakes[c.name] ?? 0) + 1;
      _mistakes[c.name] = n;
      if (n == tipAfterMistakes) tips.add(c);
    }
    final top = verdict.topFailed;
    if (top == null) return CueDecision(tips: tips);
    final last = _lastSpokenMs[top.cue];
    final safety = top.category == CheckCategory.safety;
    final speak =
        voiceOn && (safety || last == null || tMs - last >= cueRepeatMs);
    if (speak) _lastSpokenMs[top.cue] = tMs;
    return CueDecision(text: top.cue, speak: speak, tips: tips);
  }

  /// New set: mistake counts and the repeat timer start over.
  void reset() {
    _lastSpokenMs.clear();
    _mistakes.clear();
  }
}
