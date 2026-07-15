import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_state.dart';
import '../../core/models.dart';
import '../../core/tts.dart';
import '../../core/visual.dart';
import '../ai/ai_sheet.dart';
import '../pronounce/pronounce_sheet.dart';

/// Full word page: card, status controls, personal notes, AI actions.
class WordDetailScreen extends StatefulWidget {
  final Word word;
  const WordDetailScreen({super.key, required this.word});

  @override
  State<WordDetailScreen> createState() => _WordDetailScreenState();
}

class _WordDetailScreenState extends State<WordDetailScreen> {
  late final TextEditingController _notes;

  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    _notes =
        TextEditingController(text: state.progressOf(widget.word.word).notes);
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final w = widget.word;
    final p = state.progressOf(w.word);

    return Scaffold(
      appBar: AppBar(
        title: Text(w.word),
        actions: [
          IconButton(
            icon: Icon(p.fav ? Icons.bookmark : Icons.bookmark_border),
            onPressed: () => state.toggleFav(w.word),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              height: 160,
              child: WordVisual(word: w.word, theme: w.theme, emojiSize: 64),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(w.word,
                        style: const TextStyle(
                            fontSize: 32, fontWeight: FontWeight.bold)),
                    if (w.ipa.isNotEmpty)
                      Text(w.ipa,
                          style: TextStyle(
                              color: Colors.grey.shade600, fontSize: 18)),
                    Text('${w.pos} · ${w.level} · ${w.theme}',
                        style: TextStyle(color: Colors.grey.shade600)),
                    const SizedBox(height: 8),
                    Text(w.ru, style: const TextStyle(fontSize: 22)),
                  ],
                ),
              ),
              Column(
                children: [
                  IconButton.filledTonal(
                    onPressed: () => Tts.speak(w.word, rate: state.ttsRate),
                    icon: const Icon(Icons.volume_up),
                  ),
                  IconButton.filledTonal(
                    onPressed: () => showPronounceSheet(context, w),
                    icon: const Icon(Icons.mic),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (w.examples.isNotEmpty) ...[
            Text('Примеры', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final e in w.examples)
              Card(
                child: ListTile(
                  title: Text(e.en),
                  subtitle: Text(e.ru),
                  trailing: IconButton(
                    icon: const Icon(Icons.volume_up, size: 20),
                    onPressed: () => Tts.speak(e.en, rate: state.ttsRate),
                  ),
                ),
              ),
            const SizedBox(height: 16),
          ],
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => state.markKnown(w.word),
                  child: Text(
                      p.status == WordStatus.known ? 'Знаю ✓' : 'Знаю'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => state.startLearning(w.word),
                  child: Text(p.status == WordStatus.learning ||
                          p.status == WordStatus.mastered
                      ? 'Учу ✓'
                      : 'Учить'),
                ),
              ),
            ],
          ),
          if (state.aiConfigured) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => showAiSheet(context, w),
              icon: const Icon(Icons.auto_awesome),
              label: const Text('AI: объяснение, примеры, моё предложение'),
            ),
          ],
          const SizedBox(height: 16),
          Text('Мои пометки', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _notes,
            maxLines: 3,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Ассоциации, нюансы употребления…',
            ),
            onChanged: (v) => state.saveNotes(w.word, v),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
