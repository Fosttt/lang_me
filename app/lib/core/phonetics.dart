/// Оценка произношения: сравнение распознанного текста с целевым.
///
/// Балл 0–100 считается из максимума посимвольной и фонетической близости
/// (упрощённый метафон для английского + расстояние Левенштейна), с поправкой
/// на confidence распознавателя.
library;

String cleanWord(String s) =>
    s.toLowerCase().replaceAll(RegExp(r"[^a-z']"), '');

List<String> tokenize(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r"[^a-z'\s]"), ' ')
    .split(RegExp(r'\s+'))
    .where((w) => w.isNotEmpty)
    .toList();

/// Упрощённый фонетический ключ английского слова (в духе Metaphone):
/// нормализует типичные написания одного звука к одному символу.
String phoneticKey(String word) {
  var w = cleanWord(word).replaceAll("'", '');
  if (w.isEmpty) return '';

  // частые орфографические группы -> звук
  const groups = <String, String>{
    'ough': 'o',
    'augh': 'a',
    'tion': 'xn',
    'sion': 'xn',
    'sch': 'sk',
    'tch': 'x',
    'dge': 'j',
    'igh': 'i',
    'ph': 'f',
    'gh': '',
    'ck': 'k',
    'wr': 'r',
    'kn': 'n',
    'gn': 'n',
    'mb': 'm',
    'wh': 'w',
    'sh': 'x',
    'ch': 'x',
    'th': '0',
    'qu': 'kw',
    'ce': 'se',
    'ci': 'si',
    'cy': 'si',
    'ge': 'je',
    'gi': 'ji',
    'gy': 'ji',
  };
  groups.forEach((k, v) => w = w.replaceAll(k, v));

  w = w.replaceAll('c', 'k').replaceAll('q', 'k').replaceAll('z', 's');
  // немое e на конце
  if (w.length > 2 && w.endsWith('e')) w = w.substring(0, w.length - 1);
  // сдвоенные буквы
  w = w.replaceAllMapped(RegExp(r'(.)\1+'), (m) => m.group(1)!);
  // все гласные к одному классу, кроме первой буквы
  if (w.length > 1) {
    w = w[0] + w.substring(1).replaceAll(RegExp(r'[aeiouy]'), 'a');
  }
  w = w.replaceAllMapped(RegExp(r'(.)\1+'), (m) => m.group(1)!);
  return w;
}

int levenshtein(String a, String b) {
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var prev = List<int>.generate(b.length + 1, (i) => i);
  final cur = List<int>.filled(b.length + 1, 0);
  for (var i = 1; i <= a.length; i++) {
    cur[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      cur[j] = [cur[j - 1] + 1, prev[j] + 1, prev[j - 1] + cost]
          .reduce((x, y) => x < y ? x : y);
    }
    prev.setAll(0, cur);
  }
  return prev[b.length];
}

double similarity(String a, String b) {
  if (a.isEmpty && b.isEmpty) return 1;
  if (a.isEmpty || b.isEmpty) return 0;
  final maxLen = a.length > b.length ? a.length : b.length;
  return 1 - levenshtein(a, b) / maxLen;
}

/// Насколько произнесённое слово похоже на целевое, 0..1.
double wordMatch(String target, String heard) {
  final t = cleanWord(target);
  final h = cleanWord(heard);
  if (t.isEmpty || h.isEmpty) return 0;
  if (t == h) return 1;
  final raw = similarity(t, h);
  final phon = similarity(phoneticKey(t), phoneticKey(h));
  final combined = 0.35 * raw + 0.65 * phon;
  return combined > raw ? combined : raw;
}

/// Балл 0–100 за одиночное слово. [recognized] — вся распознанная фраза
/// (берём лучшее слово из неё), [confidence] 0..1 от распознавателя.
int scoreWord(String target, String recognized, double confidence) {
  final words = tokenize(recognized);
  if (words.isEmpty) return 0;
  var best = 0.0;
  for (final w in words) {
    final m = wordMatch(target, w);
    if (m > best) best = m;
  }
  // распознанное лишнее вокруг слова слегка штрафуем
  if (words.length > 2) best *= 0.95;
  final conf = confidence <= 0 ? 1.0 : confidence.clamp(0.3, 1.0);
  final score = best * (0.85 + 0.15 * conf) * 100;
  return score.round().clamp(0, 100);
}

/// Посимвольная подсветка для слова: true = буква «попала».
/// Выравнивание LCS между целевым словом и лучшим распознанным.
List<bool> charHighlight(String target, String recognized) {
  final t = cleanWord(target);
  final words = tokenize(recognized);
  var bestWord = '';
  var best = -1.0;
  for (final w in words) {
    final m = wordMatch(target, w);
    if (m > best) {
      best = m;
      bestWord = w;
    }
  }
  final h = cleanWord(bestWord);
  // LCS-таблица
  final n = t.length, m = h.length;
  final dp = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  for (var i = 1; i <= n; i++) {
    for (var j = 1; j <= m; j++) {
      dp[i][j] = t[i - 1] == h[j - 1]
          ? dp[i - 1][j - 1] + 1
          : (dp[i - 1][j] > dp[i][j - 1] ? dp[i - 1][j] : dp[i][j - 1]);
    }
  }
  final hit = List<bool>.filled(n, false);
  var i = n, j = m;
  while (i > 0 && j > 0) {
    if (t[i - 1] == h[j - 1]) {
      hit[i - 1] = true;
      i--;
      j--;
    } else if (dp[i - 1][j] >= dp[i][j - 1]) {
      i--;
    } else {
      j--;
    }
  }
  return hit;
}

class SentenceResult {
  final List<bool> wordHits; // по словам целевого предложения
  final int score; // 0–100 = доля правильных слов

  SentenceResult(this.wordHits, this.score);
}

/// Пословное сравнение предложения: выравнивание распознанных слов с целевыми
/// (LCS с нечётким равенством), балл = доля совпавших слов.
SentenceResult scoreSentence(String target, String recognized) {
  final tw = tokenize(target);
  final rw = tokenize(recognized);
  final n = tw.length, m = rw.length;
  bool eq(String a, String b) => wordMatch(a, b) >= 0.75;

  final dp = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  for (var i = 1; i <= n; i++) {
    for (var j = 1; j <= m; j++) {
      dp[i][j] = eq(tw[i - 1], rw[j - 1])
          ? dp[i - 1][j - 1] + 1
          : (dp[i - 1][j] > dp[i][j - 1] ? dp[i - 1][j] : dp[i][j - 1]);
    }
  }
  final hits = List<bool>.filled(n, false);
  var i = n, j = m;
  while (i > 0 && j > 0) {
    if (eq(tw[i - 1], rw[j - 1])) {
      hits[i - 1] = true;
      i--;
      j--;
    } else if (dp[i - 1][j] >= dp[i][j - 1]) {
      i--;
    } else {
      j--;
    }
  }
  final score =
      n == 0 ? 0 : (hits.where((h) => h).length / n * 100).round();
  return SentenceResult(hits, score);
}
