import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/ai_client.dart';
import '../../core/app_state.dart';
import '../../core/models.dart';

/// AI actions for a word (needs the personal LLM server to be configured):
/// explain differently, more examples, check my own sentence.
Future<void> showAiSheet(BuildContext context, Word word) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _AiSheet(word: word),
  );
}

class _AiSheet extends StatefulWidget {
  final Word word;
  const _AiSheet({required this.word});

  @override
  State<_AiSheet> createState() => _AiSheetState();
}

class _AiSheetState extends State<_AiSheet> {
  final _sentence = TextEditingController();
  String? _result;
  bool _loading = false;

  AiClient _client(AppState state) =>
      AiClient(baseUrl: state.serverUrl, token: state.serverToken);

  Future<void> _run(Future<String> Function() action) async {
    setState(() {
      _loading = true;
      _result = null;
    });
    try {
      final text = await action();
      if (mounted) setState(() => _result = text);
    } catch (e) {
      if (mounted) setState(() => _result = '⚠️ $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _sentence.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final w = widget.word;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('AI · ${w.word}',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _loading
                        ? null
                        : () => _run(() => _client(state).explain(w.word, w.ru)),
                    icon: const Icon(Icons.lightbulb_outline, size: 18),
                    label: const Text('Объясни иначе'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _loading
                        ? null
                        : () =>
                            _run(() => _client(state).examples(w.word, w.ru)),
                    icon: const Icon(Icons.format_list_bulleted, size: 18),
                    label: const Text('Ещё примеры'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _sentence,
              maxLines: 2,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: 'Моё предложение со словом «${w.word}»',
                hintText: 'Напиши предложение — LLM проверит',
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _loading
                  ? null
                  : () {
                      final s = _sentence.text.trim();
                      if (s.isEmpty) return;
                      _run(() => _client(state).check(w.word, s));
                    },
              icon: const Icon(Icons.spellcheck, size: 18),
              label: const Text('Проверить предложение'),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                  child: Column(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 8),
                      Text('Думаю… (обычно 5–20 секунд)'),
                    ],
                  ),
                ),
              ),
            if (_result != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SelectableText(_result!),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
