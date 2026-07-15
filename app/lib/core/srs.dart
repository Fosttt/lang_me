import 'models.dart';

/// SM-2 spaced repetition (Anki-style grades: again / hard / good / easy).
enum Grade { again, hard, good, easy }

void applyGrade(Progress p, Grade g) {
  final now = DateTime.now().millisecondsSinceEpoch;
  switch (g) {
    case Grade.again:
      p.reps = 0;
      p.lapses += 1;
      p.interval = 0;
      p.ef = (p.ef - 0.20).clamp(1.3, 3.0);
      // retry in 10 minutes
      p.due = now + 10 * 60 * 1000;
      break;
    case Grade.hard:
      p.ef = (p.ef - 0.15).clamp(1.3, 3.0);
      p.interval = p.interval <= 0 ? 0.5 : p.interval * 1.2;
      p.reps += 1;
      p.due = now + (p.interval * 24 * 60 * 60 * 1000).round();
      break;
    case Grade.good:
      if (p.reps == 0) {
        p.interval = 1;
      } else if (p.reps == 1) {
        p.interval = 6;
      } else {
        p.interval = p.interval * p.ef;
      }
      p.reps += 1;
      p.due = now + (p.interval * 24 * 60 * 60 * 1000).round();
      break;
    case Grade.easy:
      p.ef = (p.ef + 0.15).clamp(1.3, 3.0);
      if (p.reps == 0) {
        p.interval = 3;
      } else {
        p.interval = p.interval * p.ef * 1.3;
      }
      p.reps += 1;
      p.due = now + (p.interval * 24 * 60 * 60 * 1000).round();
      break;
  }
  if (p.status == WordStatus.learning && p.interval >= 21) {
    p.status = WordStatus.mastered;
  } else if (p.status == WordStatus.mastered && p.interval < 21) {
    p.status = WordStatus.learning;
  }
}
