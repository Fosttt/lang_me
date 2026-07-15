/// Data models: a dictionary word and the user's learning progress for it.

class Example {
  final String en;
  final String ru;
  const Example({required this.en, required this.ru});

  factory Example.fromJson(Map<String, dynamic> j) =>
      Example(en: j['en'] as String, ru: j['ru'] as String);

  Map<String, dynamic> toJson() => {'en': en, 'ru': ru};
}

class Word {
  final String word;
  final String ipa;
  final String pos; // part of speech
  final String level; // A1..C2
  final String ru;
  final String theme;
  final List<Example> examples;

  const Word({
    required this.word,
    required this.ipa,
    required this.pos,
    required this.level,
    required this.ru,
    required this.theme,
    required this.examples,
  });

  factory Word.fromJson(Map<String, dynamic> j) => Word(
        word: j['word'] as String,
        ipa: (j['ipa'] ?? '') as String,
        pos: (j['pos'] ?? '') as String,
        level: (j['level'] ?? 'A1') as String,
        ru: j['ru'] as String,
        theme: (j['theme'] ?? 'other') as String,
        examples: ((j['examples'] ?? []) as List)
            .map((e) => Example.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

const List<String> kLevels = ['A1', 'A2', 'B1', 'B2', 'C1', 'C2'];

int levelIndex(String level) {
  final i = kLevels.indexOf(level);
  return i < 0 ? 0 : i;
}

/// Learning status of a word.
/// unseen = never interacted; learning = in SRS rotation;
/// known = user said "I know it"; mastered = SRS interval >= 21 days.
enum WordStatus { unseen, learning, known, mastered }

class Progress {
  final String word;
  WordStatus status;
  bool fav;
  String notes;
  // SM-2 fields
  double ef; // easiness factor
  double interval; // days
  int reps;
  int lapses;
  int due; // epoch ms when next review is due

  Progress({
    required this.word,
    this.status = WordStatus.unseen,
    this.fav = false,
    this.notes = '',
    this.ef = 2.5,
    this.interval = 0,
    this.reps = 0,
    this.lapses = 0,
    this.due = 0,
  });

  factory Progress.fromMap(Map<String, dynamic> m) => Progress(
        word: m['word'] as String,
        status: WordStatus.values[(m['status'] ?? 0) as int],
        fav: ((m['fav'] ?? 0) as int) == 1,
        notes: (m['notes'] ?? '') as String,
        ef: ((m['ef'] ?? 2.5) as num).toDouble(),
        interval: ((m['interval'] ?? 0) as num).toDouble(),
        reps: (m['reps'] ?? 0) as int,
        lapses: (m['lapses'] ?? 0) as int,
        due: (m['due'] ?? 0) as int,
      );

  Map<String, dynamic> toMap() => {
        'word': word,
        'status': status.index,
        'fav': fav ? 1 : 0,
        'notes': notes,
        'ef': ef,
        'interval': interval,
        'reps': reps,
        'lapses': lapses,
        'due': due,
      };
}
