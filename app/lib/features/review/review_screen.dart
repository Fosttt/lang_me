import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/models.dart';
import '../../core/srs.dart';
import '../../core/tts.dart';
import '../../core/visual.dart';

/// SRS review queue: front = word + audio, tap to reveal, grade with
/// again / hard / good / easy (SM-2 reschedules the card).
class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key});

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final due = state.dueReviews();

    if (due.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('✅', style: TextStyle(fontSize: 64)),
              const SizedBox(height: 16),
              Text('На сегодня всё повторено',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              const Text(
                'Добавляйте слова из ленты кнопкой «Учить» — они появятся здесь по расписанию SM-2.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final word = due.first;
    final example = word.examples.isNotEmpty ? word.examples.first : null;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Осталось: ${due.length}',
                style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _revealed = true),
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      SizedBox(
                        height: 160,
                        width: double.infinity,
                        child: WordVisual(
                            word: word.word,
                            theme: word.theme,
                            emojiSize: 64),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                word.word,
                                style: const TextStyle(
                                    fontSize: 34,
                                    fontWeight: FontWeight.bold),
                              ),
                              if (word.ipa.isNotEmpty)
                                Text(word.ipa,
                                    style: TextStyle(
                                        color: Colors.grey.shade600,
                                        fontSize: 18)),
                              IconButton(
                                onPressed: () => Tts.speak(word.word,
                                    rate: state.ttsRate),
                                icon: const Icon(Icons.volume_up),
                              ),
                              const SizedBox(height: 8),
                              if (_revealed) ...[
                                Text(word.ru,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(fontSize: 24)),
                                if (example != null) ...[
                                  const SizedBox(height: 12),
                                  Text(example.en,
                                      textAlign: TextAlign.center),
                                  Text(example.ru,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          color: Colors.grey.shade600)),
                                ],
                              ] else
                                Text('Нажмите, чтобы открыть ответ',
                                    style: TextStyle(
                                        color: Colors.grey.shade500)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_revealed)
              Row(
                children: [
                  _gradeBtn(context, state, word, Grade.again, 'Снова',
                      Colors.red),
                  _gradeBtn(context, state, word, Grade.hard, 'Трудно',
                      Colors.orange),
                  _gradeBtn(context, state, word, Grade.good, 'Хорошо',
                      Colors.blue),
                  _gradeBtn(context, state, word, Grade.easy, 'Легко',
                      Colors.green),
                ],
              )
            else
              FilledButton(
                style:
                    FilledButton.styleFrom(padding: const EdgeInsets.all(16)),
                onPressed: () => setState(() => _revealed = true),
                child: const Text('Показать ответ'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _gradeBtn(BuildContext context, AppState state, Word word, Grade g,
      String label, Color color) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: color,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          onPressed: () async {
            await state.answerReview(word.word, g);
            setState(() => _revealed = false);
          },
          child: Text(label, style: const TextStyle(fontSize: 12)),
        ),
      ),
    );
  }
}
