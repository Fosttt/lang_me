import 'package:flutter/material.dart';

/// Deterministic visuals for word cards: theme -> emoji, word hash -> gradient.
/// If assets/images/<word>.jpg|png exists it is shown instead (optional,
/// user can drop their own pictures into the folder before building).

const Map<String, String> kThemeEmoji = {
  'food': '🍎',
  'drink': '☕',
  'travel': '✈️',
  'home': '🏠',
  'family': '👨‍👩‍👧',
  'work': '💼',
  'money': '💰',
  'nature': '🌳',
  'animals': '🐾',
  'weather': '🌦️',
  'body': '💪',
  'health': '🩺',
  'clothes': '👕',
  'city': '🏙️',
  'transport': '🚌',
  'education': '🎓',
  'sport': '⚽',
  'art': '🎨',
  'music': '🎵',
  'technology': '💻',
  'science': '🔬',
  'feelings': '😊',
  'time': '⏰',
  'people': '🧑‍🤝‍🧑',
  'communication': '💬',
  'law': '⚖️',
  'business': '📈',
  'other': '✨',
};

String themeEmoji(String theme) => kThemeEmoji[theme] ?? '✨';

/// Two gradient colors derived from the word's hash — stable per word.
List<Color> wordGradient(String word) {
  final h = word.codeUnits.fold<int>(17, (a, c) => (a * 31 + c) & 0x7fffffff);
  final hue1 = (h % 360).toDouble();
  final hue2 = ((h ~/ 360) % 360).toDouble();
  return [
    HSLColor.fromAHSL(1, hue1, 0.55, 0.45).toColor(),
    HSLColor.fromAHSL(1, hue2, 0.60, 0.30).toColor(),
  ];
}

/// Full-bleed visual block for a word card.
class WordVisual extends StatelessWidget {
  final String word;
  final String theme;
  final double emojiSize;

  const WordVisual({
    super.key,
    required this.word,
    required this.theme,
    this.emojiSize = 96,
  });

  @override
  Widget build(BuildContext context) {
    final colors = wordGradient(word);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
      child: Center(
        child: Text(themeEmoji(theme), style: TextStyle(fontSize: emojiSize)),
      ),
    );
  }
}
