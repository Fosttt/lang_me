import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/ai_client.dart';
import '../../core/app_state.dart';
import '../../core/db.dart';

/// Mini tutor chat: the server weaves my recently studied words into the
/// conversation. History is stored locally.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  List<Map<String, String>> _messages = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await AppDb.chatHistory();
    setState(() {
      _messages = rows
          .map((r) => {
                'role': r['role'] as String,
                'text': r['text'] as String,
              })
          .toList();
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _loading) return;
    final state = context.read<AppState>();
    _input.clear();
    setState(() {
      _messages.add({'role': 'user', 'text': text});
      _loading = true;
    });
    await AppDb.chatAdd('user', text);
    _scrollDown();
    try {
      final client =
          AiClient(baseUrl: state.serverUrl, token: state.serverToken);
      final recent = state
          .studiedWords()
          .map((w) => w.word)
          .toList()
          .reversed
          .take(15)
          .toList();
      // последние 12 реплик как контекст
      final history = _messages.length > 12
          ? _messages.sublist(_messages.length - 12)
          : _messages;
      final reply = await client.chat(history, recent);
      await AppDb.chatAdd('assistant', reply);
      if (mounted) {
        setState(() => _messages.add({'role': 'assistant', 'text': reply}));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _messages.add({'role': 'assistant', 'text': '⚠️ $e'}));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
      _scrollDown();
    }
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI-репетитор'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Очистить историю',
            onPressed: () async {
              await AppDb.chatClear();
              setState(() => _messages = []);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        'Напиши что-нибудь по-английски — репетитор ответит и вплетёт в разговор твои недавние слова.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(12),
                    itemCount: _messages.length,
                    itemBuilder: (context, i) {
                      final m = _messages[i];
                      final mine = m['role'] == 'user';
                      return Align(
                        alignment: mine
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.all(12),
                          constraints: BoxConstraints(
                              maxWidth:
                                  MediaQuery.of(context).size.width * 0.8),
                          decoration: BoxDecoration(
                            color: mine
                                ? Theme.of(context)
                                    .colorScheme
                                    .primaryContainer
                                : Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: SelectableText(m['text'] ?? ''),
                        ),
                      );
                    },
                  ),
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(8),
              child: LinearProgressIndicator(),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      decoration: const InputDecoration(
                        hintText: 'Write in English…',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _loading ? null : _send,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
