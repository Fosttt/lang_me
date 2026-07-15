import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import 'models.dart';

/// Loads the bundled word database from assets/words.json.
class WordsRepo {
  static Future<List<Word>> load() async {
    final raw = await rootBundle.loadString('assets/words.json');
    final list = jsonDecode(raw) as List;
    final words =
        list.map((e) => Word.fromJson(e as Map<String, dynamic>)).toList();
    // stable order: by level, then alphabetically
    words.sort((a, b) {
      final l = levelIndex(a.level).compareTo(levelIndex(b.level));
      return l != 0 ? l : a.word.compareTo(b.word);
    });
    return words;
  }
}
