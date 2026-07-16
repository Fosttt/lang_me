import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/db.dart';
import '../../core/dialogs_repo.dart';
import '../../core/phonetics.dart';
import '../../core/speech_service.dart';
import '../../core/tts.dart';

/// Прохождение диалога-сценки (механика word-flow): бот произносит свои
/// реплики, тебе показывается русский текст твоей реплики — говоришь её
/// по-английски в микрофон; слова подсвечиваются зелёным/красным, ≥60 баллов
/// = зачёт, после двух неудач фраза открывается; в конце — итог.
class SceneDialogScreen extends StatefulWidget {
  final SceneDialog dialog;
  const SceneDialogScreen({super.key, required this.dialog});

  @override
  State<SceneDialogScreen> createState() => _SceneDialogScreenState();
}

class _Bubble {
  final SceneTurn turn;
  final List<bool>? hits; // пословная подсветка (для user)
  final int? score;
  final bool skipped;
  _Bubble(this.turn, {this.hits, this.score, this.skipped = false});
}

enum _Phase { userTask, listening, finished }

class _SceneDialogScreenState extends State<SceneDialogScreen> {
  final List<_Bubble> _bubbles = [];
  final _scroll = ScrollController();
  int _cursor = 0;
  _Phase _phase = _Phase.userTask;

  // состояние текущей реплики user
  int _attempts = 0;
  bool _revealed = false;
  String _partial = '';
  String? _failText;
  List<bool>? _failHits;
  int? _failScore;
  String? _errorMsg;

  final List<int> _scores = [];
  int _firstTry = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _advance());
  }

  @override
  void dispose() {
    _scroll.dispose();
    SpeechService.instance.stopListening();
    Tts.stop();
    super.dispose();
  }

  SceneTurn? get _currentUserTurn =>
      _cursor < widget.dialog.turns.length &&
              widget.dialog.turns[_cursor].isUser
          ? widget.dialog.turns[_cursor]
          : null;

  /// Продвигает диалог: показывает bot-реплики до ближайшей user-реплики.
  void _advance() {
    final state = context.read<AppState>();
    while (_cursor < widget.dialog.turns.length &&
        !widget.dialog.turns[_cursor].isUser) {
      final turn = widget.dialog.turns[_cursor];
      _bubbles.add(_Bubble(turn));
      Tts.speak(turn.en, rate: state.ttsRate);
      _cursor++;
    }
    if (_cursor >= widget.dialog.turns.length) {
      _finish();
    } else {
      setState(() {
        _phase = _Phase.userTask;
        _attempts = 0;
        _revealed = false;
        _failText = null;
        _failHits = null;
        _failScore = null;
        _errorMsg = null;
        _partial = '';
      });
    }
    _scrollDown();
  }

  Future<void> _finish() async {
    final avg = _scores.isEmpty
        ? 0
        : (_scores.reduce((a, b) => a + b) / _scores.length).round();
    await AppDb.saveDialogResult(widget.dialog.id, avg);
    if (mounted) await context.read<AppState>().bumpActivity();
    if (!mounted) return;
    setState(() => _phase = _Phase.finished);
    _scrollDown();
  }

  Future<void> _listen() async {
    final target = _currentUserTurn;
    if (target == null) return;
    await Tts.stop();
    setState(() {
      _phase = _Phase.listening;
      _partial = '';
      _errorMsg = null;
    });

    final attempt = await SpeechService.instance.listenOnce(
      timeout: const Duration(seconds: 10),
      onPartial: (p) {
        if (mounted) setState(() => _partial = p);
      },
    );
    if (!mounted) return;

    if (attempt.failed) {
      setState(() {
        _phase = _Phase.userTask;
        _errorMsg = attempt.error;
      });
      return;
    }

    _attempts++;
    final res = scoreSentence(target.en, attempt.recognized);
    if (res.score >= 60) {
      if (_attempts == 1) _firstTry++;
      _scores.add(res.score);
      _bubbles.add(_Bubble(target, hits: res.wordHits, score: res.score));
      _cursor++;
      _advance();
    } else {
      setState(() {
        _phase = _Phase.userTask;
        _failText = attempt.recognized;
        _failHits = res.wordHits;
        _failScore = res.score;
        if (_attempts >= 2) _revealed = true; // после 2 неудач показываем текст
      });
    }
    _scrollDown();
  }

  void _skip() {
    final target = _currentUserTurn;
    if (target == null) return;
    _scores.add(0);
    _bubbles.add(_Bubble(target, skipped: true));
    _cursor++;
    _advance();
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.dialog.emoji} ${widget.dialog.titleRu}'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.all(16),
                children: [
                  for (final b in _bubbles) _bubble(theme, b),
                  if (_phase == _Phase.finished) _summary(theme),
                ],
              ),
            ),
            if (_phase != _Phase.finished) _bottomPanel(theme),
          ],
        ),
      ),
    );
  }

  Widget _bubble(ThemeData theme, _Bubble b) {
    final isUser = b.turn.isUser;
    final muted = theme.colorScheme.onSurfaceVariant;

    Widget content;
    if (isUser && b.hits != null) {
      content = _coloredSentence(theme, b.turn.en, b.hits!);
    } else {
      content = Text(b.turn.en,
          style: theme.textTheme.bodyLarge?.copyWith(
              color: b.skipped ? muted : null,
              fontStyle: b.skipped ? FontStyle.italic : null));
    }

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.82),
        decoration: BoxDecoration(
          color: isUser
              ? theme.colorScheme.primaryContainer.withOpacity(0.6)
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!isUser)
                  GestureDetector(
                    onTap: () => Tts.speak(b.turn.en,
                        rate: context.read<AppState>().ttsRate),
                    child: Icon(Icons.volume_up,
                        size: 18, color: theme.colorScheme.primary),
                  ),
                if (!isUser) const SizedBox(width: 6),
                Flexible(child: content),
              ],
            ),
            const SizedBox(height: 4),
            Text(b.turn.ru,
                style: theme.textTheme.bodySmall?.copyWith(color: muted)),
            if (b.score != null || b.skipped)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  b.skipped ? 'пропущено' : '${b.score} баллов',
                  style: theme.textTheme.labelSmall?.copyWith(
                      color: b.skipped
                          ? muted
                          : b.score! >= 80
                              ? Colors.green
                              : Colors.orange,
                      fontWeight: FontWeight.bold),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _coloredSentence(ThemeData theme, String text, List<bool> hits) {
    final display = text.split(RegExp(r'\s+'));
    final spans = <TextSpan>[];
    var wi = 0;
    for (final d in display) {
      final isWord = cleanWord(d).isNotEmpty;
      final hit = isWord && wi < hits.length && hits[wi];
      spans.add(TextSpan(
        text: '$d ',
        style: TextStyle(
          color: !isWord
              ? null
              : hit
                  ? Colors.green
                  : Colors.red,
          fontWeight: FontWeight.w600,
        ),
      ));
      if (isWord) wi++;
    }
    return Text.rich(TextSpan(children: spans),
        style: theme.textTheme.bodyLarge);
  }

  Widget _bottomPanel(ThemeData theme) {
    final target = _currentUserTurn;
    if (target == null) return const SizedBox.shrink();
    final muted = theme.colorScheme.onSurfaceVariant;
    final listening = _phase == _Phase.listening;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Твоя реплика — скажи по-английски:',
              style: theme.textTheme.labelMedium?.copyWith(color: muted)),
          const SizedBox(height: 6),
          Text(target.ru,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center),
          if (_revealed)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(target.en,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(color: theme.colorScheme.primary),
                  textAlign: TextAlign.center),
            ),
          if (listening)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_partial.isEmpty ? 'Слушаю…' : _partial,
                  style: theme.textTheme.bodyMedium?.copyWith(color: muted)),
            ),
          if (_failText != null && !listening)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Column(
                children: [
                  _coloredSentence(theme, target.en, _failHits ?? const []),
                  Text(
                      'Распознано: «$_failText» · $_failScore баллов — попробуй ещё',
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                      textAlign: TextAlign.center),
                ],
              ),
            ),
          if (_errorMsg != null && !listening)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_errorMsg!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: Colors.orange),
                  textAlign: TextAlign.center),
            ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton.filledTonal(
                onPressed: () => setState(() => _revealed = true),
                icon: const Icon(Icons.lightbulb_outline),
                tooltip: 'Показать фразу',
              ),
              const SizedBox(width: 16),
              GestureDetector(
                onTap: listening
                    ? () => SpeechService.instance.stopListening()
                    : _listen,
                child: Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: listening ? Colors.red : theme.colorScheme.primary,
                  ),
                  child: Icon(listening ? Icons.stop : Icons.mic,
                      color: Colors.white, size: 32),
                ),
              ),
              const SizedBox(width: 16),
              IconButton.filledTonal(
                onPressed: _revealed
                    ? () => Tts.speak(target.en,
                        rate: context.read<AppState>().ttsRate)
                    : _skip,
                icon: Icon(_revealed ? Icons.volume_up : Icons.skip_next),
                tooltip: _revealed ? 'Послушать' : 'Пропустить',
              ),
            ],
          ),
          if (_revealed)
            TextButton(onPressed: _skip, child: const Text('Пропустить')),
        ],
      ),
    );
  }

  Widget _summary(ThemeData theme) {
    final avg = _scores.isEmpty
        ? 0
        : (_scores.reduce((a, b) => a + b) / _scores.length).round();
    return Card(
      color: theme.colorScheme.primaryContainer.withOpacity(0.4),
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(
                avg >= 80
                    ? '🏆'
                    : avg >= 60
                        ? '👍'
                        : '💪',
                style: const TextStyle(fontSize: 48)),
            const SizedBox(height: 8),
            Text('Диалог пройден!', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Средний балл: $avg\n'
              'С первой попытки: $_firstTry из ${_scores.length}',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                          builder: (_) =>
                              SceneDialogScreen(dialog: widget.dialog))),
                  child: const Text('Ещё раз'),
                ),
                const SizedBox(width: 12),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Готово'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
