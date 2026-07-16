import 'package:sqflite/sqflite.dart';

import 'models.dart';

/// Local storage: progress, daily activity, AI response cache, chat history.
class AppDb {
  static Database? _db;

  static Future<Database> open() async {
    if (_db != null) return _db!;
    final path = '${await getDatabasesPath()}/lang_me.db';
    _db = await openDatabase(
      path,
      version: 2,
      onUpgrade: (db, oldV, newV) async {
        if (oldV < 2) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS dialog_result(
              id TEXT PRIMARY KEY,
              score INTEGER NOT NULL
            )''');
        }
      },
      onCreate: (db, v) async {
        await db.execute('''
          CREATE TABLE dialog_result(
            id TEXT PRIMARY KEY,
            score INTEGER NOT NULL
          )''');
        await db.execute('''
          CREATE TABLE progress(
            word TEXT PRIMARY KEY,
            status INTEGER NOT NULL DEFAULT 0,
            fav INTEGER NOT NULL DEFAULT 0,
            notes TEXT NOT NULL DEFAULT '',
            ef REAL NOT NULL DEFAULT 2.5,
            interval REAL NOT NULL DEFAULT 0,
            reps INTEGER NOT NULL DEFAULT 0,
            lapses INTEGER NOT NULL DEFAULT 0,
            due INTEGER NOT NULL DEFAULT 0
          )''');
        await db.execute('''
          CREATE TABLE activity(
            day TEXT PRIMARY KEY,
            count INTEGER NOT NULL DEFAULT 0
          )''');
        await db.execute('''
          CREATE TABLE ai_cache(
            k TEXT PRIMARY KEY,
            v TEXT NOT NULL
          )''');
        await db.execute('''
          CREATE TABLE chat(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            role TEXT NOT NULL,
            text TEXT NOT NULL,
            ts INTEGER NOT NULL
          )''');
      },
    );
    return _db!;
  }

  static Future<Map<String, Progress>> loadProgress() async {
    final db = await open();
    final rows = await db.query('progress');
    return {for (final r in rows) r['word'] as String: Progress.fromMap(r)};
  }

  static Future<void> saveProgress(Progress p) async {
    final db = await open();
    await db.insert('progress', p.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<Map<String, int>> loadActivity() async {
    final db = await open();
    final rows = await db.query('activity');
    return {for (final r in rows) r['day'] as String: r['count'] as int};
  }

  static Future<void> saveActivity(String day, int count) async {
    final db = await open();
    await db.insert('activity', {'day': day, 'count': count},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<String?> cacheGet(String key) async {
    final db = await open();
    final rows =
        await db.query('ai_cache', where: 'k = ?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : rows.first['v'] as String;
  }

  static Future<void> cachePut(String key, String value) async {
    final db = await open();
    await db.insert('ai_cache', {'k': key, 'v': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<List<Map<String, dynamic>>> chatHistory() async {
    final db = await open();
    return db.query('chat', orderBy: 'id ASC', limit: 200);
  }

  static Future<void> chatAdd(String role, String text) async {
    final db = await open();
    await db.insert('chat', {
      'role': role,
      'text': text,
      'ts': DateTime.now().millisecondsSinceEpoch,
    });
  }

  static Future<void> chatClear() async {
    final db = await open();
    await db.delete('chat');
  }

  /// Лучший результат по каждому пройденному диалогу-сценке.
  static Future<Map<String, int>> dialogProgress() async {
    final db = await open();
    final rows = await db.query('dialog_result');
    return {for (final r in rows) r['id'] as String: r['score'] as int};
  }

  static Future<void> saveDialogResult(String id, int score) async {
    final db = await open();
    final prev = await db.query('dialog_result',
        where: 'id = ?', whereArgs: [id], limit: 1);
    final best = prev.isEmpty
        ? score
        : (prev.first['score'] as int) > score
            ? prev.first['score'] as int
            : score;
    await db.insert('dialog_result', {'id': id, 'score': best},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> resetAll() async {
    final db = await open();
    await db.delete('progress');
    await db.delete('activity');
    await db.delete('ai_cache');
    await db.delete('chat');
    await db.delete('dialog_result');
  }
}
