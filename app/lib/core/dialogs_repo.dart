import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// Сценка-диалог: бот говорит свои реплики, пользователь произносит свои
/// по-английски, глядя на русский текст. Формат совместим с word-flow.
class SceneTurn {
  final String role; // 'bot' | 'user'
  final String en;
  final String ru;

  const SceneTurn({required this.role, required this.en, required this.ru});

  bool get isUser => role == 'user';

  factory SceneTurn.fromJson(Map<String, dynamic> j) => SceneTurn(
        role: j['role'] as String,
        en: j['en'] as String,
        ru: j['ru'] as String,
      );
}

class SceneDialog {
  final String id;
  final String level;
  final String titleRu;
  final String emoji;
  final List<SceneTurn> turns;

  const SceneDialog({
    required this.id,
    required this.level,
    required this.titleRu,
    required this.emoji,
    required this.turns,
  });

  int get userTurnCount => turns.where((t) => t.isUser).length;

  factory SceneDialog.fromJson(Map<String, dynamic> j) => SceneDialog(
        id: j['id'] as String,
        level: j['level'] as String,
        titleRu: j['title_ru'] as String,
        emoji: (j['emoji'] ?? '💬') as String,
        turns: (j['turns'] as List)
            .map((t) => SceneTurn.fromJson(t as Map<String, dynamic>))
            .toList(),
      );
}

class DialogsRepo {
  static List<SceneDialog>? _cache;

  static Future<List<SceneDialog>> load() async {
    if (_cache != null) return _cache!;
    final raw = await rootBundle.loadString('assets/dialogs.json');
    _cache = (jsonDecode(raw) as List)
        .map((e) => SceneDialog.fromJson(e as Map<String, dynamic>))
        .toList();
    return _cache!;
  }

  static Map<String, List<SceneDialog>> byLevel(List<SceneDialog> all) {
    final map = <String, List<SceneDialog>>{};
    for (final d in all) {
      map.putIfAbsent(d.level, () => []).add(d);
    }
    return map;
  }
}
