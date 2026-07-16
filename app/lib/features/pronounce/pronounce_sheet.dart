import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/models.dart';
import '../../core/phonetics.dart';
import '../../core/speech_service.dart';
import '../../core/tts.dart';

/// Практика произношения слова: нажми микрофон, произнеси, получи вердикт
/// по фонетическому скорингу (общий SpeechService, как в диалогах).
Future<void> showPronounceSheet(BuildContext context, Word word) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _PronounceSheet(word: word),
  );
}

class _PronounceSheet extends StatefulWidget {
  final Word word;
  const _PronounceSheet({required this.word});

  @override
  State<_PronounceSheet> createState() => _PronounceSheetState();
}

class _PronounceSheetState extends State<_PronounceSheet> {
  bool _listening = false;
  String _heard = '';
  String? _verdict;
  String? _error;
  Color _verdictColor = Colors.grey;

  Future<void> _start() async {
    if (_listening) {
      await SpeechService.instance.stopListening();
      return;
    }
    await Tts.stop();
    setState(() {
      _listening = true;
      _heard = '';
      _verdict = null;
      _error = null;
    });
    final attempt = await SpeechService.instance.listenOnce(
      timeout: const Duration(seconds: 6),
      onPartial: (p) {
        if (mounted) setState(() => _heard = p);
      },
    );
    if (!mounted) return;
    if (attempt.failed) {
      setState(() {
        _listening = false;
        _error = attempt.error;
      });
      return;
    }
    final score =
        scoreWord(widget.word.word, attempt.recognized, attempt.confidence);
    String verdict;
    Color color;
    if (score >= 80) {
      verdict = 'Отлично! 🎯 ($score)';
      color = Colors.green;
    } else if (score >= 55) {
      verdict = 'Близко — ещё разок 👍 ($score)';
      color = Colors.orange;
    } else {
      verdict = 'Попробуй ещё 🙂 ($score)';
      color = Colors.red;
    }
    setState(() {
      _listening = false;
      _heard = attempt.recognized;
      _verdict = verdict;
      _verdictColor = color;
    });
  }

  @override
  void dispose() {
    SpeechService.instance.stopListening();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Произнеси слово',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            widget.word.word,
            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
          ),
          if (widget.word.ipa.isNotEmpty)
            Text(widget.word.ipa,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 18)),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => Tts.speak(widget.word.word, rate: state.ttsRate),
            icon: const Icon(Icons.volume_up),
            label: const Text('Послушать образец'),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: _start,
            child: CircleAvatar(
              radius: 44,
              backgroundColor: _listening
                  ? Colors.red
                  : Theme.of(context).colorScheme.primary,
              child: Icon(
                _listening ? Icons.stop : Icons.mic,
                color: Colors.white,
                size: 40,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(_listening ? 'Слушаю… (нажми ещё раз — стоп)' : 'Нажми и говори'),
          const SizedBox(height: 16),
          if (_heard.isNotEmpty)
            Text('Услышал: «$_heard»',
                style: TextStyle(color: Colors.grey.shade600)),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.orange)),
            ),
          if (_verdict != null) ...[
            const SizedBox(height: 8),
            Text(
              _verdict!,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: _verdictColor,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
