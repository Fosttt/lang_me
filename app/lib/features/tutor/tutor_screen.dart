import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../core/ai_client.dart';
import '../../core/app_state.dart';
import '../../core/db.dart';
import '../../core/tts.dart';

/// Interactive tutor conversation (main "Диалог" tab):
/// the tutor asks in English, the user answers by voice or text, mistakes
/// come back corrected with a short RU note, and every tutor line hides its
/// translation behind a tap. Recent studied words are woven in.
class TutorScreen extends StatefulWidget {
  const TutorScreen({super.key});

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
  final SpeechToText _speech = SpeechToText();
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
      await _speech.stop();
      setState(() => _listening = false);
      return;
    }
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
    if (!ok || !mounted) return;
    setState(() => _listening = true);
    await _speech.listen(
      localeId: 'en_US',
      listenFor: const Duration(seconds: 15),
      onResult: (r) {
        _input.text = r.recognizedWords;
        _input.selection =
            TextSelection.collapsed(offset: _input.text.length);
      },
    );
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
    _speech.stop();
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
                Text('Диалог',
                    style: Theme.of(context).textTheme.headlineSmall),
                const Spacer(),
                IconButton(
                  tooltip: 'Новый диалог',
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
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Row(
              children: [
                IconButton.filledTonal(
                  onPressed: _dictate,
                  icon: Icon(_listening ? Icons.graphic_eq : Icons.mic,
                      color: _listening ? Colors.red : null),
                  tooltip: 'Ответить голосом',
                ),
                const SizedBox(width: 8),
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
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _loading ? null : _send,
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bubble(BuildContext context, _TutorMsg m) {
    final scheme = Theme.of(context).colorScheme;
    final state = context.read<AppState>();
    final mine = m.role == 'user';

    return Column(
      crossAxisAlignment:
          mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        // правка ответа ученика — над репликой репетитора
        if (m.fix != null)
          Container(
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.all(10),
            constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.85),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.18),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.shade600, width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('✏️ Правильнее: ${m.fix}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                if (m.fixNote != null && m.fixNote!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(m.fixNote!,
                        style:
                            TextStyle(fontSize: 13, color: scheme.outline)),
                  ),
              ],
            ),
          ),
        GestureDetector(
          // тап по реплике репетитора открывает/прячет перевод
          onTap: mine || m.ru.isEmpty
              ? null
              : () => setState(() => m.showRu = !m.showRu),
          onLongPress: mine
              ? null
              : () => Tts.speak(m.text, rate: state.ttsRate),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 5),
            padding: const EdgeInsets.all(12),
            constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.82),
            decoration: BoxDecoration(
              color: mine ? scheme.primaryContainer : scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m.text, style: const TextStyle(fontSize: 16)),
                if (!mine && m.ru.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  if (m.showRu)
                    Text(m.ru,
                        style: TextStyle(
                            fontSize: 14, color: scheme.outline))
                  else
                    Text('👆 перевод',
                        style: TextStyle(
                            fontSize: 12,
                            color: scheme.outline.withOpacity(0.7))),
                ],
              ],
            ),
          ),
        ),
        if (!mine)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text('долгий тап — озвучить',
                style: TextStyle(
                    fontSize: 10,
                    color: scheme.outline.withOpacity(0.5))),
          ),
      ],
    );
  }
}
