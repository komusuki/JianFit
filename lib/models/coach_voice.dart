// How Coach Zhang speaks (Settings > Coach voice). CueSpeaker applies it.
enum CoachVoice {
  english('English', 'en-US'),
  mandarinEnglish('Mandarin voice, English cues', 'zh-CN'),
  mandarin('Mandarin (中文)', 'zh-CN');

  const CoachVoice(this.label, this.locale);

  final String label;

  /// The text-to-speech language. The phone must have it installed;
  /// otherwise CueSpeaker falls back to English.
  final String locale;
}

/// Spoken Mandarin for each cue in the exercise files. A cue missing here is
/// spoken in English. On-screen cues stay English.
/// Draft translations: have a Mandarin speaker check them.
const mandarinCues = {
  'Bend your front knee more.': '前腿再弯一点。',
  'Elbows under your shoulders.': '手肘放在肩膀正下方。',
  'Go lower before you jump.': '跳之前再蹲低一点。',
  'Go lower.': '再低一点。',
  'Jump up.': '向上跳。',
  'Keep your chest up.': '挺胸。',
  'Keep your front knee over your ankle.': '前膝保持在脚踝正上方。',
  'Keep your heels down.': '脚跟不要离地。',
  'Land softly. Bend your knees.': '轻轻落地，膝盖弯曲。',
  'Lift your hips. Keep a straight line.': '臀部抬起来，身体保持一条直线。',
  'Lift your hips.': '臀部抬起来。',
  'Lower your back knee.': '后膝再低一点。',
  'Lower your hips.': '臀部放低。',
};
