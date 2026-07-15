import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/models.dart';
import '../../core/tts.dart';
import 'word_card.dart';

/// Vertical full-screen word feed (TikTok-style, infinite scroll).
class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  final _controller = PageController();
  List<Word> _pool = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshPool());
  }

  void _refreshPool() {
    final state = context.read<AppState>();
    setState(() => _pool = state.feedWords());
    if (_pool.isNotEmpty && state.autoSpeak) {
      Tts.speak(_pool.first.word, rate: state.ttsRate);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (_pool.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🎉', style: TextStyle(fontSize: 64)),
              const SizedBox(height: 16),
              const Text(
                'Новых слов для ленты нет — все разобраны. Загляните в «Повторение» или смените уровень в настройках.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                  onPressed: _refreshPool, child: const Text('Обновить')),
            ],
          ),
        ),
      );
    }
    return PageView.builder(
      controller: _controller,
      scrollDirection: Axis.vertical,
      onPageChanged: (i) {
        final w = _pool[i % _pool.length];
        if (state.autoSpeak) Tts.speak(w.word, rate: state.ttsRate);
      },
      itemBuilder: (context, i) {
        final w = _pool[i % _pool.length];
        return WordCard(
          word: w,
          onHandled: () {
            // после «знаю»/«учить» листаем дальше
            _controller.nextPage(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          },
        );
      },
    );
  }
}
