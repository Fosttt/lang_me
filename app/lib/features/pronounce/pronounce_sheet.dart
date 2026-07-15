import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../core/app_state.dart';
import '../../core/models.dart';
import '../../core/tts.dart';

/// Pronunciation practice: press the mic, say the word, get instant feedback
/// (exact match / close by edit distance / try again). Offline recognition.
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
  final SpeechToText _speech = SpeechToText();
  bool _available = true;
  bool _listening = false;
  String _heard = '';
  String? _verdict; // null = ещё не пробовал
  Color _verdictColor = Colors.grey;

  Future<void> _start() async {
    setState(() {
      _heard = '';
      _verdict = null;
    });
    final ok = await _speech.initialize(
      onStatus: (s) {
        if (s == 'notListening' && mounted) {
          setState(() => _listening = false);
        }
      },
      onError: (_) {
        if (mounted) setState(() => _listening = false);
      },
    );
    if (!ok) {
      setState(() => _available = false);
      return;
    }
    setState(() => _listening = true);
    await _speech.listen(
      localeId: 'en_US',
      listenFor: const Duration(seconds: 5),
      onResult: _onResult,
    );
  }

  void _onResult(SpeechRecognitionResult result) {
    final heard = result.recognizedWords.toLowerCase().trim();
    if (heard.isEmpty) return;
    final target = widget.word.word.toLowerCase();
    final tokens = heard.split(RegExp(r'\s+'));
    var best = 999;
    for (final t in tokens) {
      final d = _levenshtein(t, target);
      if (d < best) best = d;
    }
    // фраза целиком тоже считается
    best = best < _levenshtein(heard, target)
        ? best
        : _levenshtein(heard, target);

    String verdict;
    Color color;
    if (best == 0) {
      verdict = 'Отлично! 🎯';
      color = Colors.green;
    } else if (best <= 2) {
      verdict = 'Близко — ещё разок 👍';
      color = Colors.orange;
    } else {
      verdict = 'Попробуй ещё 🙂';
      color = Colors.red;
    }
    setState(() {
      _heard = heard;
      _verdict = verdict;
      _verdictColor = color;
      _listening = false;
    });
  }

  static int _levenshtein(String a, String b) {
    if (a == b) return 0;
    final m = a.length, n = b.length;
    if (m == 0) return n;
    if (n == 0) return m;
    var prev = List<int>.generate(n + 1, (i) => i);
    var curr = List<int>.filled(n + 1, 0);
    for (var i = 1; i <= m; i++) {
      curr[0] = i;
      for (var j = 1; j <= n; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        curr[j] = [
          curr[j - 1] + 1,
          prev[j] + 1,
          prev[j - 1] + cost,
        ].reduce((x, y) => x < y ? x : y);
      }
      final tmp = prev;
      prev = curr;
      curr = tmp;
    }
    return prev[n];
  }

  @override
  void dispose() {
    _speech.stop();
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
          if (!_available)
            const Text(
              'Распознавание речи недоступно на этом устройстве. Проверьте разрешение на микрофон.',
              textAlign: TextAlign.center,
            )
          else ...[
            GestureDetector(
              onTap: _listening ? null : _start,
              child: CircleAvatar(
                radius: 44,
                backgroundColor: _listening
                    ? Colors.red
                    : Theme.of(context).colorScheme.primary,
                child: Icon(
                  _listening ? Icons.graphic_eq : Icons.mic,
                  color: Colors.white,
                  size: 40,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(_listening ? 'Слушаю…' : 'Нажми и говори'),
          ],
          const SizedBox(height: 16),
          if (_heard.isNotEmpty)
            Text('Услышал: «$_heard»',
                style: TextStyle(color: Colors.grey.shade600)),
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
