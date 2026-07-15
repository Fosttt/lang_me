import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ai_config.dart';
import 'db.dart';
import 'models.dart';
import 'srs.dart';
import 'words_repo.dart';

String dayKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Global app state: settings, word list, per-word progress, daily activity.
class AppState extends ChangeNotifier {
  late SharedPreferences _prefs;

  List<Word> words = [];
  Map<String, Progress> progress = {};
  Map<String, int> activity = {};

  // settings
  String level = 'A2';
  bool darkTheme = false;
  bool autoSpeak = true;
  double ttsRate = 0.5; // 0..1
  int dailyGoal = 20;
  String serverUrl = '';
  String serverToken = '';
  bool placementDone = false;

  bool loaded = false;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    level = _prefs.getString('level') ?? 'A2';
    darkTheme = _prefs.getBool('darkTheme') ?? false;
    autoSpeak = _prefs.getBool('autoSpeak') ?? true;
    ttsRate = _prefs.getDouble('ttsRate') ?? 0.5;
    dailyGoal = _prefs.getInt('dailyGoal') ?? 20;
    // если пользователь ничего не настраивал — берём вшитые в сборку значения
    serverUrl = _prefs.getString('serverUrl') ?? '';
    serverToken = _prefs.getString('serverToken') ?? '';
    if (serverUrl.isEmpty) serverUrl = kDefaultAiUrl;
    if (serverToken.isEmpty) serverToken = kDefaultAiToken;
    placementDone = _prefs.getBool('placementDone') ?? false;

    words = await WordsRepo.load();
    progress = await AppDb.loadProgress();
    activity = await AppDb.loadActivity();
    loaded = true;
    notifyListeners();
  }

  bool get aiConfigured => serverUrl.isNotEmpty && serverToken.isNotEmpty;

  // ---------- settings ----------

  Future<void> saveSettings({
    String? level,
    bool? darkTheme,
    bool? autoSpeak,
    double? ttsRate,
    int? dailyGoal,
    String? serverUrl,
    String? serverToken,
    bool? placementDone,
  }) async {
    if (level != null) this.level = level;
    if (darkTheme != null) this.darkTheme = darkTheme;
    if (autoSpeak != null) this.autoSpeak = autoSpeak;
    if (ttsRate != null) this.ttsRate = ttsRate;
    if (dailyGoal != null) this.dailyGoal = dailyGoal;
    if (serverUrl != null) this.serverUrl = serverUrl.trim();
    if (serverToken != null) this.serverToken = serverToken.trim();
    if (placementDone != null) this.placementDone = placementDone;

    await _prefs.setString('level', this.level);
    await _prefs.setBool('darkTheme', this.darkTheme);
    await _prefs.setBool('autoSpeak', this.autoSpeak);
    await _prefs.setDouble('ttsRate', this.ttsRate);
    await _prefs.setInt('dailyGoal', this.dailyGoal);
    await _prefs.setString('serverUrl', this.serverUrl);
    await _prefs.setString('serverToken', this.serverToken);
    await _prefs.setBool('placementDone', this.placementDone);
    notifyListeners();
  }

  // ---------- progress ----------

  Progress progressOf(String word) =>
      progress[word] ?? Progress(word: word);

  Future<void> _put(Progress p) async {
    progress[p.word] = p;
    await AppDb.saveProgress(p);
    notifyListeners();
  }

  Future<void> markKnown(String word) async {
    final p = progressOf(word)..status = WordStatus.known;
    await _put(p);
    await bumpActivity();
  }

  Future<void> startLearning(String word) async {
    final p = progressOf(word);
    if (p.status == WordStatus.unseen || p.status == WordStatus.known) {
      p.status = WordStatus.learning;
      p.due = DateTime.now().millisecondsSinceEpoch;
    }
    await _put(p);
    await bumpActivity();
  }

  Future<void> toggleFav(String word) async {
    final p = progressOf(word)..fav = !progressOf(word).fav;
    await _put(p);
  }

  Future<void> saveNotes(String word, String notes) async {
    final p = progressOf(word)..notes = notes;
    await _put(p);
  }

  Future<void> answerReview(String word, Grade g) async {
    final p = progressOf(word);
    applyGrade(p, g);
    await _put(p);
    await bumpActivity();
  }

  // ---------- derived lists ----------

  Word? wordByName(String name) {
    for (final w in words) {
      if (w.word == name) return w;
    }
    return null;
  }

  /// Feed: words of the user's level first, then neighbours; skips
  /// known/mastered. Shuffled deterministically per day.
  List<Word> feedWords() {
    final li = levelIndex(level);
    final pool = words.where((w) {
      final st = progressOf(w.word).status;
      return st == WordStatus.unseen || st == WordStatus.learning;
    }).toList();
    int dist(Word w) => (levelIndex(w.level) - li).abs();
    final seed = dayKey(DateTime.now()).hashCode;
    pool.shuffle(Random(seed));
    pool.sort((a, b) => dist(a).compareTo(dist(b)));
    return pool;
  }

  List<Word> dueReviews() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final due = words.where((w) {
      final p = progressOf(w.word);
      return (p.status == WordStatus.learning ||
              p.status == WordStatus.mastered) &&
          p.due <= now;
    }).toList();
    due.sort((a, b) => progressOf(a.word).due.compareTo(progressOf(b.word).due));
    return due;
  }

  /// Words the user has interacted with — pool for training modes and chat.
  List<Word> studiedWords() => words.where((w) {
        final st = progressOf(w.word).status;
        return st != WordStatus.unseen;
      }).toList();

  List<Word> favoriteWords() =>
      words.where((w) => progressOf(w.word).fav).toList();

  int countByStatus(WordStatus s) =>
      progress.values.where((p) => p.status == s).length;

  // ---------- activity / streak ----------

  Future<void> bumpActivity() async {
    final key = dayKey(DateTime.now());
    final v = (activity[key] ?? 0) + 1;
    activity[key] = v;
    await AppDb.saveActivity(key, v);
    notifyListeners();
  }

  int get streak {
    var d = DateTime.now();
    var s = 0;
    // today counts if there is activity; otherwise streak may still be alive
    // from yesterday.
    if ((activity[dayKey(d)] ?? 0) == 0) d = d.subtract(const Duration(days: 1));
    while ((activity[dayKey(d)] ?? 0) > 0) {
      s += 1;
      d = d.subtract(const Duration(days: 1));
    }
    return s;
  }

  int get todayCount => activity[dayKey(DateTime.now())] ?? 0;

  // ---------- export / import ----------

  String exportJson() {
    return jsonEncode({
      'version': 1,
      'exported': DateTime.now().toIso8601String(),
      'settings': {
        'level': level,
        'dailyGoal': dailyGoal,
      },
      'progress': progress.values.map((p) => p.toMap()).toList(),
      'activity': activity,
    });
  }

  Future<String> importJson(String raw) async {
    final data = jsonDecode(raw) as Map<String, dynamic>;
    final items = (data['progress'] as List).cast<Map<String, dynamic>>();
    for (final m in items) {
      final p = Progress.fromMap(m);
      progress[p.word] = p;
      await AppDb.saveProgress(p);
    }
    final act = (data['activity'] ?? {}) as Map<String, dynamic>;
    for (final e in act.entries) {
      activity[e.key] = (e.value as num).toInt();
      await AppDb.saveActivity(e.key, activity[e.key]!);
    }
    final st = (data['settings'] ?? {}) as Map<String, dynamic>;
    if (st['level'] is String) await saveSettings(level: st['level'] as String);
    notifyListeners();
    return 'Импортировано слов: ${items.length}';
  }

  Future<void> resetProgress() async {
    await AppDb.resetAll();
    progress = {};
    activity = {};
    await saveSettings(placementDone: false);
  }
}
