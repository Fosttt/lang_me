import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/models.dart';
import '../../core/tts.dart';
import '../review/review_screen.dart';

/// Training hub: four modes over the words the user has already touched.
class TrainingScreen extends StatelessWidget {
  const TrainingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final pool = state.studiedWords();
    final enough = pool.length >= 4;

    final modes = [
      (_Mode.enRu, Icons.translate, 'Перевод EN → RU',
          'Выбери перевод из четырёх'),
      (_Mode.ruEn, Icons.swap_horiz, 'Перевод RU → EN',
          'Выбери слово по переводу'),
      (_Mode.letters, Icons.abc, 'Сборка слова',
          'Собери слово из букв по переводу'),
      (_Mode.audio, Icons.hearing, 'Аудирование',
          'Услышь слово и найди его'),
    ];

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Тренировка', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(
            enough
                ? 'В пуле ${pool.length} изученных слов'
                : 'Отметьте хотя бы 4 слова в ленте («Учить» или «Знаю»), чтобы открыть тренировки.',
            style: TextStyle(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 16),
          Card(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: ListTile(
              leading: Badge(
                isLabelVisible: state.dueReviews().isNotEmpty,
                label: Text('${state.dueReviews().length}'),
                child: const Icon(Icons.refresh, size: 32),
              ),
              title: const Text('Повторение (SM-2)'),
              subtitle: Text(state.dueReviews().isEmpty
                  ? 'На сегодня всё повторено'
                  : 'Слов к повторению: ${state.dueReviews().length}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => Scaffold(
                    appBar: AppBar(title: const Text('Повторение')),
                    body: const ReviewScreen(),
                  ),
                ),
              ),
            ),
          ),
          for (final (mode, icon, title, subtitle) in modes)
            Card(
              child: ListTile(
                leading: Icon(icon, size: 32),
                title: Text(title),
                subtitle: Text(subtitle),
                trailing: const Icon(Icons.chevron_right),
                enabled: enough,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => _SessionScreen(mode: mode),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

enum _Mode { enRu, ruEn, letters, audio }

class _SessionScreen extends StatefulWidget {
  final _Mode mode;
  const _SessionScreen({required this.mode});

  @override
  State<_SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<_SessionScreen> {
  static const int _total = 10;

  final _rng = Random();
  late List<Word> _pool;
  int _asked = 0;
  int _correct = 0;
  Word? _current;
  List<String> _options = [];
  // сборка из букв
  List<String> _letters = [];
  List<int> _pickedIdx = [];
  bool _done = false;
  String? _flash; // подсветка результата ответа

  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    _pool = List.of(state.studiedWords())..shuffle(_rng);
    _next();
  }

  void _next() {
    if (_asked >= _total || _asked >= _pool.length) {
      setState(() => _done = true);
      return;
    }
    final w = _pool[_asked];
    final state = context.read<AppState>();
    final others = state.words.where((x) => x.word != w.word).toList()
      ..shuffle(_rng);

    switch (widget.mode) {
      case _Mode.enRu:
        _options = [w.ru, ...others.take(3).map((x) => x.ru)]..shuffle(_rng);
        break;
      case _Mode.ruEn:
      case _Mode.audio:
        _options = [w.word, ...others.take(3).map((x) => x.word)]
          ..shuffle(_rng);
        break;
      case _Mode.letters:
        _letters = w.word.split('')..shuffle(_rng);
        _pickedIdx = [];
        _options = [];
        break;
    }
    setState(() {
      _current = w;
      _flash = null;
    });
    if (widget.mode == _Mode.audio) {
      Tts.speak(w.word, rate: state.ttsRate);
    }
  }

  Future<void> _answer(bool ok) async {
    final state = context.read<AppState>();
    if (ok) _correct += 1;
    await state.bumpActivity();
    setState(() => _flash = ok ? 'ok' : 'fail');
    await Future.delayed(const Duration(milliseconds: 600));
    _asked += 1;
    _next();
  }

  String get _built =>
      _pickedIdx.map((i) => _letters[i]).join();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (_done) {
      return Scaffold(
        appBar: AppBar(title: const Text('Результат')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_correct >= _asked * 0.7 ? '🏆' : '💪',
                  style: const TextStyle(fontSize: 64)),
              const SizedBox(height: 16),
              Text('$_correct из $_asked верно',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Готово'),
              ),
            ],
          ),
        ),
      );
    }

    final w = _current;
    if (w == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    String prompt;
    switch (widget.mode) {
      case _Mode.enRu:
        prompt = w.word;
        break;
      case _Mode.ruEn:
      case _Mode.letters:
        prompt = w.ru;
        break;
      case _Mode.audio:
        prompt = '🔊';
        break;
    }

    return Scaffold(
      appBar: AppBar(title: Text('Вопрос ${_asked + 1} из $_total')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LinearProgressIndicator(value: _asked / _total),
            const Spacer(),
            GestureDetector(
              onTap: widget.mode == _Mode.audio
                  ? () => Tts.speak(w.word, rate: state.ttsRate)
                  : null,
              child: Text(
                prompt,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 34, fontWeight: FontWeight.bold),
              ),
            ),
            if (widget.mode == _Mode.audio)
              TextButton.icon(
                onPressed: () => Tts.speak(w.word, rate: state.ttsRate),
                icon: const Icon(Icons.replay),
                label: const Text('Повторить звук'),
              ),
            const Spacer(),
            if (_flash != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _flash == 'ok' ? 'Верно ✅' : 'Неверно ❌  (${w.word} — ${w.ru})',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: _flash == 'ok' ? Colors.green : Colors.red,
                  ),
                ),
              ),
            if (widget.mode == _Mode.letters) ...[
              Text(
                _built.isEmpty ? '···' : _built,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 28, letterSpacing: 2),
              ),
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < _letters.length; i++)
                    ActionChip(
                      label: Text(_letters[i],
                          style: const TextStyle(fontSize: 20)),
                      onPressed: _pickedIdx.contains(i) || _flash != null
                          ? null
                          : () {
                              setState(() => _pickedIdx.add(i));
                              if (_pickedIdx.length == _letters.length) {
                                _answer(_built == w.word);
                              }
                            },
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _pickedIdx.isEmpty || _flash != null
                    ? null
                    : () => setState(() => _pickedIdx.removeLast()),
                child: const Text('⌫ Убрать букву'),
              ),
            ] else
              for (final opt in _options)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    onPressed: _flash != null
                        ? null
                        : () => _answer(
                              widget.mode == _Mode.enRu
                                  ? opt == w.ru
                                  : opt == w.word,
                            ),
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
