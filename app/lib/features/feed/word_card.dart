import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/models.dart';
import '../../core/tts.dart';
import '../../core/visual.dart';
import '../ai/ai_sheet.dart';
import '../pronounce/pronounce_sheet.dart';

/// One full-screen card of the feed: visual, word, transcription, translation,
/// example, action buttons (know / learn / fav / speak / mic / AI).
class WordCard extends StatelessWidget {
  final Word word;
  final VoidCallback? onHandled;

  const WordCard({super.key, required this.word, this.onHandled});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final p = state.progressOf(word.word);
    final example = word.examples.isNotEmpty ? word.examples.first : null;

    return Stack(
      fit: StackFit.expand,
      children: [
        WordVisual(word: word.word, theme: word.theme),
        // затемнение снизу для читаемости
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Colors.black87],
              stops: [0.35, 1],
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _chip(word.level),
                    const SizedBox(width: 8),
                    _chip(word.pos),
                    const Spacer(),
                    IconButton(
                      onPressed: () => state.toggleFav(word.word),
                      icon: Icon(
                        p.fav ? Icons.bookmark : Icons.bookmark_border,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            word.word,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 40,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (word.ipa.isNotEmpty)
                            Text(
                              word.ipa,
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 18),
                            ),
                          const SizedBox(height: 4),
                          Text(
                            word.ru,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 22),
                          ),
                          if (example != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              example.en,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 16),
                            ),
                            Text(
                              example.ru,
                              style: const TextStyle(
                                  color: Colors.white60, fontSize: 14),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Column(
                      children: [
                        _roundBtn(
                          icon: Icons.volume_up,
                          onTap: () =>
                              Tts.speak(word.word, rate: state.ttsRate),
                        ),
                        const SizedBox(height: 12),
                        _roundBtn(
                          icon: Icons.mic,
                          onTap: () => showPronounceSheet(context, word),
                        ),
                        if (state.aiConfigured) ...[
                          const SizedBox(height: 12),
                          _roundBtn(
                            icon: Icons.auto_awesome,
                            onTap: () => showAiSheet(context, word),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white54),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: () async {
                          await state.markKnown(word.word);
                          onHandled?.call();
                        },
                        child: const Text('Знаю'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: () async {
                          await state.startLearning(word.word);
                          onHandled?.call();
                        },
                        child: const Text('Учить'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _chip(String text) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black38,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text,
          style: const TextStyle(color: Colors.white, fontSize: 12)),
    );
  }

  Widget _roundBtn({required IconData icon, required VoidCallback onTap}) {
    return Material(
      color: Colors.black38,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Icon(icon, color: Colors.white, size: 26),
        ),
      ),
    );
  }
}
