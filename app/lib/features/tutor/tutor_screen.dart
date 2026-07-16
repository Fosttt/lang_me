import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/ai_client.dart';
import '../../core/app_state.dart';
import '../../core/db.dart';
import '../../core/speech_service.dart';
import '../../core/tts.dart';

/// Interactive tutor conversation (main "Диалог" tab):
/// the tutor asks in English, the user answers by voice or text, mistakes
/// come back corrected with a short RU note, and every tutor line hides its
/// translation behind a tap. Recent studied words are woven in.
class TutorScreen extends StatefulWidget {
  /// [showHeader] — собственный заголовок с кнопкой сброса; false, когда
  /// экран открыт внутри Scaffold с AppBar.
  final bool showHeader;
  const TutorScreen({super.key, this.showHeader = true});

  @override
  State<TutorScreen> createState() => _TutorScreenState();
}

class _TutorMsg {
  final String role; // 'user' | 'tutor'
  final String text; // EN
  final String ru; // перевод (для tutor)
  final String? fix; // правка последнего ответа ученика
  final String? fixNote; // пояснение по-русски
  bool showRu = false;

  _TutorMsg({
    required this.role,
    required this.text,
    this.ru = '',
    this.fix,
    this.fixNote,
  });

  String encode() => jsonEncode({
        'text': text,
        'ru': ru,
        'fix': fix,
        'fix_note': fixNote,
      });

  static _TutorMsg decode(String role, String raw) {
    if (role == 'user') return _TutorMsg(role: 'user', text: raw);
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return _TutorMsg(
        role: 'tutor',
        text: (j['text'] ?? '') as String,
        ru: (j['ru'] ?? '') as String,
        fix: j['fix'] as String?,
        fixNote: j['fix_note'] as String?,
      );
    } catch (_) {
      return _TutorMsg(role: 'tutor', text: raw);
    }
  }
}

class _TutorScreenState extends State<TutorScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<_TutorMsg> _messages = [];
  bool _loading = false;
  bool _listening = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await AppDb.chatHistory();
    setState(() {
      _messages.clear();
      _messages.addAll(rows.map(
          (r) => _TutorMsg.decode(r['role'] as String, r['text'] as String)));
    });
    if (_messages.isEmpty) {
      _requestTurn(); // репетитор здоровается и задаёт первый вопрос
    } else {
      _scrollDown();
    }
  }

  List<Map<String, String>> _historyForServer() {
    final recent = _messages.length > 12
        ? _messages.sublist(_messages.length - 12)
        : _messages;
    return [
      for (final m in recent)
        {'role': m.role == 'user' ? 'user' : 'assistant', 'text': m.text}
    ];
  }

  Future<void> _requestTurn() async {
    final state = context.read<AppState>();
    if (!state.aiConfigured) return;
    setState(() => _loading = true);
    try {
      final client =
          AiClient(baseUrl: state.serverUrl, token: state.serverToken);
      final recentWords = state
          .studiedWords()
          .map((w) => w.word)
          .toList()
          .reversed
          .take(15)
          .toList();
      final r = await client.tutor(_historyForServer(), recentWords);
      final msg = _TutorMsg(
        role: 'tutor',
        text: (r['text'] ?? '') as String,
        ru: (r['ru'] ?? '') as String,
        fix: r['fix'] as String?,
        fixNote: r['fix_note'] as String?,
      );
      await AppDb.chatAdd('tutor', msg.encode());
      if (!mounted) return;
      setState(() => _messages.add(msg));
      if (state.autoSpeak && msg.text.isNotEmpty) {
        Tts.speak(msg.text, rate: state.ttsRate);
      }
      await state.bumpActivity();
    } catch (e) {
      if (mounted) {
        setState(() =>
            _messages.add(_TutorMsg(role: 'tutor', text: '⚠️ $e', ru: '')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
      _scrollDown();
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _loading) return;
    _input.clear();
    final msg = _TutorMsg(role: 'user', text: text);
    await AppDb.chatAdd('user', text);
    setState(() => _messages.add(msg));
    _scrollDown();
    await _requestTurn();
  }

  Future<void> _dictate() async {
    if (_listening) {
      await SpeechService.instance.stopListening();
      return;
    }
    await Tts.stop();
    setState(() => _listening = true);
    final attempt = await SpeechService.instance.listenOnce(
      timeout: const Duration(seconds: 15),
      onPartial: (p) {
        _input.text = p;
        _input.selection =
            TextSelection.collapsed(offset: _input.text.length);
      },
    );
    if (!mounted) return;
    setState(() => _listening = false);
    if (!attempt.failed) {
      _input.text = attempt.recognized;
      _input.selection = TextSelection.collapsed(offset: _input.text.length);
    }
  }

  Future<void> _restart() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Начать новый диалог?'),
        content: const Text('Текущая переписка будет удалена.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Начать заново')),
        ],
      ),
    );
    if (ok != true) return;
    await AppDb.chatClear();
    setState(() => _messages.clear());
    _requestTurn();
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
    SpeechService.instance.stopListening();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (!state.aiConfigured) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Диалог с репетитором требует AI-сервера. Укажите URL и токен в Профиль → Настройки.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
            child: Row(
              children: [
                if (widget.showHeader)
                  Text('Разговор',
                      style: Theme.of(context).textTheme.headlineSmall),
                const Spacer(),
                IconButton(
                  tooltip: 'Новый разговор',
                  onPressed: _restart,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(12),
              itemCount: _messages.length,
              itemBuilder: (context, i) => _bubble(context, _messages[i]),
            ),
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: LinearProgressIndicator(),
            ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_listening)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text('Слушаю… говори по-английски',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant)),
                  ),
                Row(
                  children: [
                    GestureDetector(
                      onTap: _dictate,
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _listening
                              ? Colors.red
                              : Theme.of(context).colorScheme.primary,
                        ),
                        child: Icon(_listening ? Icons.stop : Icons.mic,
                            color: Colors.white, size: 24),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _input,
                        decoration: const InputDecoration(
                          hintText: 'Answer in English…',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    IconButton.filled(
                      onPressed: _loading ? null : _send,
                      icon: const Icon(Icons.send),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bubble(BuildContext context, _TutorMsg m) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final state = context.read<AppState>();
    final mine = m.role == 'user';

    return Column(
      crossAxisAlignment:
          mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        // правка ответа ученика — над репликой репетитора
        if (m.fix != null)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.82),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.15),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: Colors.amber.withOpacity(0.6), width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('✏️ Правильнее: ${m.fix}',
                    style: theme.textTheme.bodyLarge
                        ?.copyWith(fontWeight: FontWeight.w600)),
                if (m.fixNote != null && m.fixNote!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(m.fixNote!,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: muted)),
                  ),
              ],
            ),
          ),
        GestureDetector(
          // тап по реплике репетитора открывает/прячет перевод
          onTap: mine || m.ru.isEmpty
              ? null
              : () => setState(() => m.showRu = !m.showRu),
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.82),
            decoration: BoxDecoration(
              color: mine
                  ? theme.colorScheme.primaryContainer.withOpacity(0.6)
                  : theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(mine ? 16 : 4),
                bottomRight: Radius.circular(mine ? 4 : 16),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!mine)
                      GestureDetector(
                        onTap: () =>
                            Tts.speak(m.text, rate: state.ttsRate),
                        child: Icon(Icons.volume_up,
                            size: 18, color: theme.colorScheme.primary),
                      ),
                    if (!mine) const SizedBox(width: 6),
                    Flexible(
                        child: Text(m.text,
                            style: theme.textTheme.bodyLarge)),
                  ],
                ),
                if (!mine && m.ru.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  if (m.showRu)
                    Text(m.ru,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: muted))
                  else
                    Text('перевод ▾',
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: muted.withOpacity(0.7))),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
