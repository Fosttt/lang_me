import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/models.dart';
import '../../core/visual.dart';
import 'word_detail.dart';

/// Dictionary: search over the whole base + a "saved" (favorites) tab.
class DictionaryScreen extends StatefulWidget {
  const DictionaryScreen({super.key});

  @override
  State<DictionaryScreen> createState() => _DictionaryScreenState();
}

class _DictionaryScreenState extends State<DictionaryScreen> {
  String _query = '';
  bool _favsOnly = false;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final q = _query.toLowerCase().trim();
    final list = (_favsOnly ? state.favoriteWords() : state.words)
        .where((w) =>
            q.isEmpty ||
            w.word.toLowerCase().contains(q) ||
            w.ru.toLowerCase().contains(q))
        .toList();

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'Поиск: слово или перевод',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  isSelected: _favsOnly,
                  onPressed: () => setState(() => _favsOnly = !_favsOnly),
                  icon: Icon(
                      _favsOnly ? Icons.bookmark : Icons.bookmark_border),
                  tooltip: 'Только сохранённые',
                ),
              ],
            ),
          ),
          Expanded(
            child: list.isEmpty
                ? const Center(child: Text('Ничего не найдено'))
                : ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (context, i) {
                      final w = list[i];
                      final p = state.progressOf(w.word);
                      return ListTile(
                        leading: SizedBox(
                          width: 44,
                          height: 44,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: WordVisual(
                                word: w.word, theme: w.theme, emojiSize: 22),
                          ),
                        ),
                        title: Text(w.word),
                        subtitle: Text('${w.ru} · ${w.level}'),
                        trailing: _statusIcon(p),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => WordDetailScreen(word: w)),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget? _statusIcon(Progress p) {
    switch (p.status) {
      case WordStatus.unseen:
        return null;
      case WordStatus.learning:
        return const Icon(Icons.school, color: Colors.orange, size: 20);
      case WordStatus.known:
        return const Icon(Icons.check_circle_outline,
            color: Colors.blue, size: 20);
      case WordStatus.mastered:
        return const Icon(Icons.verified, color: Colors.green, size: 20);
    }
  }
}
