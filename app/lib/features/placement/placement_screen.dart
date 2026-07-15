import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/models.dart';
import '../main_util.dart';

/// First-launch adaptive placement test (~20 questions, choose the correct
/// translation). A correct answer moves the pool one level up, a wrong one —
/// one level down; the finishing level becomes the user's level.
class PlacementScreen extends StatefulWidget {
  const PlacementScreen({super.key});

  @override
  State<PlacementScreen> createState() => _PlacementScreenState();
}

class _PlacementScreenState extends State<PlacementScreen> {
  static const int _total = 20;

  final _rng = Random();
  int _levelIdx = 1; // start at A2
  int _asked = 0;
  int _correct = 0;
  Word? _current;
  List<String> _options = [];
  bool _started = false;
  final Set<String> _used = {};

  void _next(AppState state) {
    if (_asked >= _total) {
      _finish(state);
      return;
    }
    // берём случайное слово текущего уровня (или ближайшего непустого)
    Word? pick;
    for (var d = 0; d < kLevels.length && pick == null; d++) {
      for (final idx in [_levelIdx - d, _levelIdx + d]) {
        if (idx < 0 || idx >= kLevels.length) continue;
        final pool = state.words
            .where((w) =>
                levelIndex(w.level) == idx && !_used.contains(w.word))
            .toList();
        if (pool.isNotEmpty) {
          pick = pool[_rng.nextInt(pool.length)];
          break;
        }
      }
    }
    if (pick == null) {
      _finish(state);
      return;
    }
    final chosen = pick;
    _used.add(chosen.word);
    final distractors = state.words
        .where((w) => w.word != chosen.word && w.ru != chosen.ru)
        .toList()
      ..shuffle(_rng);
    final opts = [chosen.ru, ...distractors.take(3).map((w) => w.ru)]
      ..shuffle(_rng);
    setState(() {
      _current = chosen;
      _options = opts;
    });
  }

  void _answer(AppState state, String choice) {
    final ok = choice == _current!.ru;
    if (ok) {
      _correct += 1;
      _levelIdx = min(_levelIdx + 1, kLevels.length - 2); // C2 не назначаем
    } else {
      _levelIdx = max(_levelIdx - 1, 0);
    }
    _asked += 1;
    _next(state);
  }

  Future<void> _finish(AppState state) async {
    final level = kLevels[_levelIdx];
    await state.saveSettings(level: level, placementDone: true);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Ваш уровень: $level ($_correct/$_asked верно)')),
    );
    goHome(context);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (!_started) {
      return Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('👋', style: TextStyle(fontSize: 64)),
                const SizedBox(height: 16),
                Text('Определим ваш уровень',
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center),
                const SizedBox(height: 12),
                const Text(
                  'Короткий тест из 20 вопросов: выбирайте перевод слова. Сложность подстраивается под ответы.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                FilledButton(
                  onPressed: state.loaded
                      ? () {
                          setState(() => _started = true);
                          _next(state);
                        }
                      : null,
                  child: const Text('Начать тест'),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () async {
                    await state.saveSettings(placementDone: true);
                    if (context.mounted) goHome(context);
                  },
                  child: const Text('Пропустить (уровень A2)'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final w = _current;
    return Scaffold(
      appBar: AppBar(
        title: Text('Вопрос ${_asked + 1} из $_total'),
        automaticallyImplyLeading: false,
      ),
      body: w == null
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LinearProgressIndicator(value: _asked / _total),
                  const Spacer(),
                  Text(
                    w.word,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 36, fontWeight: FontWeight.bold),
                  ),
                  if (w.ipa.isNotEmpty)
                    Text(w.ipa,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey.shade600)),
                  const Spacer(),
                  for (final opt in _options)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        onPressed: () => _answer(state, opt),
                        child: Text(opt, style: const TextStyle(fontSize: 16)),
                      ),
                    ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
    );
  }
}
