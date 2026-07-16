import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/ai_client.dart';
import '../../core/app_state.dart';
import '../../core/models.dart';
import '../../core/phonetics.dart';
import '../../core/speech_service.dart';
import '../../core/tts.dart';

/// Mini-dialogue for a word: chat bubbles A/B with distinct voices,
/// per-line audio, "play all", RU translation toggle and a practice mode
/// where the user voices speaker B and gets scored by the microphone.
///
/// Dialogues are bundled in words.json; if a word has none and the AI
/// server is configured, one is generated on the fly (and cached).
Future<void> showWordDialog(BuildContext context, Word word) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scroll) =>
          _DialogSheet(word: word, scrollController: scroll),
    ),
  );
}

class _DialogSheet extends StatefulWidget {
  final Word word;
  final ScrollController scrollController;
  const _DialogSheet({required this.word, required this.scrollController});

  @override
  State<_DialogSheet> createState() => _DialogSheetState();
}

class _DialogSheetState extends State<_DialogSheet> {
  List<DialogLine> _lines = [];
  bool _loading = false;
  String? _error;
  bool _showRu = false; // общий тоггл; отдельные реплики — долгим тапом
  final Set<int> _ruShown = {};
  bool _practice = false;
  int _playingLine = -1;
  // практика: результат по индексу реплики (null = не пробовал)
  final Map<int, bool> _practiceResult = {};
  int _listeningLine = -1;

  @override
  void initState() {
    super.initState();
    _lines = widget.word.dialog;
    if (_lines.isEmpty) _fetchFromAi();
  }

  Future<void> _fetchFromAi() async {
    final state = context.read<AppState>();
    if (!state.aiConfigured) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client =
          AiClient(baseUrl: state.serverUrl, token: state.serverToken);
      final text = await client.dialog(
          widget.word.word, widget.word.ru, widget.word.level);
      final raw = text.trim();
      final start = raw.indexOf('[');
      final end = raw.lastIndexOf(']');
      final list = jsonDecode(raw.substring(start, end + 1)) as List;
      setState(() {
        _lines = list
            .map((e) => DialogLine.fromJson(e as Map<String, dynamic>))
            .toList();
      });
    } catch (e) {
      setState(() => _error = 'Не удалось получить диалог: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  double _pitchOf(DialogLine l) => l.s == 'A' ? Tts.pitchA : Tts.pitchB;

  Future<void> _playAll() async {
    final state = context.read<AppState>();
    await Tts.speakSeq(
      [for (final l in _lines) (l.en, _pitchOf(l))],
      rate: state.ttsRate,
      onLine: (i) {
        if (mounted) setState(() => _playingLine = i);
      },
    );
  }

  // ---------- практика: пользователь озвучивает реплики B ----------

  Future<void> _practiceLine(int index) async {
    await Tts.stop();
    setState(() {
      _listeningLine = index;
      _practiceResult.remove(index);
    });
    final attempt = await SpeechService.instance
        .listenOnce(timeout: const Duration(seconds: 8));
    if (!mounted) return;
    setState(() {
      _listeningLine = -1;
      if (!attempt.failed) {
        _practiceResult[index] =
            scoreSentence(_lines[index].en, attempt.recognized).score >= 60;
      }
    });
  }

  @override
  void dispose() {
    SpeechService.instance.stopListening();
    Tts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Диалог · ${widget.word.word}',
                  style: Theme.of(context).textTheme.titleLarge,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                tooltip: 'Перевод',
                isSelected: _showRu,
                onPressed: () => setState(() => _showRu = !_showRu),
                icon: const Icon(Icons.translate),
              ),
              IconButton(
                tooltip: 'Практика: озвучь реплики B',
                isSelected: _practice,
                onPressed: _lines.isEmpty
                    ? null
                    : () => setState(() => _practice = !_practice),
                icon: const Icon(Icons.record_voice_over),
              ),
            ],
          ),
        ),
        if (_practice)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Ты — собеседник B: слушай A и произноси свои реплики в микрофон.',
              style: TextStyle(color: scheme.primary, fontSize: 13),
            ),
          ),
        Expanded(
          child: _loading
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 12),
                      Text('Сочиняю диалог… (5–20 секунд)'),
                    ],
                  ),
                )
              : _lines.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _error ??
                              'Для этого слова пока нет диалога. Обновите базу слов или настройте AI-сервер.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: widget.scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: _lines.length,
                      itemBuilder: (context, i) => _bubble(context, i),
                    ),
        ),
        if (_lines.isNotEmpty)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _playingLine >= 0
                          ? () async {
                              await Tts.stop();
                              setState(() => _playingLine = -1);
                            }
                          : _playAll,
                      icon: Icon(_playingLine >= 0
                          ? Icons.stop
                          : Icons.play_arrow),
                      label: Text(_playingLine >= 0
                          ? 'Остановить'
                          : 'Прослушать весь диалог'),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _bubble(BuildContext context, int i) {
    final l = _lines[i];
    final state = context.read<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final isA = l.s == 'A';
    final playing = _playingLine == i;
    final hidden = _practice && !isA && _practiceResult[i] == null;

    final result = _practiceResult[i];
    Color bg;
    if (playing) {
      bg = scheme.tertiaryContainer;
    } else if (result == true) {
      bg = Colors.green.withOpacity(0.25);
    } else if (result == false) {
      bg = Colors.red.withOpacity(0.2);
    } else {
      bg = isA ? scheme.surfaceContainerHighest : scheme.primaryContainer;
    }

    return Align(
      alignment: isA ? Alignment.centerLeft : Alignment.centerRight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (!isA && _practice) ...[
            IconButton(
              onPressed:
                  _listeningLine == i ? null : () => _practiceLine(i),
              icon: Icon(
                _listeningLine == i ? Icons.graphic_eq : Icons.mic,
                color: _listeningLine == i ? Colors.red : scheme.primary,
              ),
            ),
          ],
          Flexible(
            child: GestureDetector(
              onTap: hidden
                  ? () => setState(() => _practiceResult[i] = false)
                  : () => Tts.speak(l.en,
                      rate: state.ttsRate, pitch: _pitchOf(l)),
              onLongPress: hidden
                  ? null
                  : () => setState(() => _ruShown.contains(i)
                      ? _ruShown.remove(i)
                      : _ruShown.add(i)),
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 5),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.72),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(16),
                    topRight: const Radius.circular(16),
                    bottomLeft: Radius.circular(isA ? 4 : 16),
                    bottomRight: Radius.circular(isA ? 16 : 4),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${l.s} ${isA ? '👩' : '👨'}',
                        style: TextStyle(
                            fontSize: 11, color: scheme.outline)),
                    const SizedBox(height: 2),
                    Text(
                      hidden ? '🎤 Произнеси свою реплику…' : l.en,
                      style: const TextStyle(fontSize: 16),
                    ),
                    if ((_showRu || _ruShown.contains(i)) && !hidden) ...[
                      const SizedBox(height: 2),
                      Text(l.ru,
                          style: TextStyle(
                              fontSize: 13, color: scheme.outline)),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
