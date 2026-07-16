import 'dart:async';

import 'package:speech_to_text/speech_to_text.dart';

/// Результат одной попытки распознавания.
class SpeechAttempt {
  final String recognized;
  final double confidence; // 0..1, -1 если неизвестно
  final String? error; // человекочитаемая ошибка, если распознать не удалось

  SpeechAttempt({this.recognized = '', this.confidence = -1, this.error});

  bool get failed => error != null;
}

/// Однофразовое распознавание поверх системного SpeechRecognizer
/// (портировано из word-flow — там механика уже обкатана).
class SpeechService {
  SpeechService._();
  static final SpeechService instance = SpeechService._();

  final SpeechToText _stt = SpeechToText();

  bool _initialized = false;
  bool _available = false;
  String? _lastError;
  void Function()? _onSessionDone;

  bool get isListening => _stt.isListening;

  Future<bool> init() async {
    if (_initialized) return _available;
    try {
      _available = await _stt.initialize(
        onError: (e) {
          _lastError = e.errorMsg;
          _scheduleDone();
        },
        onStatus: (status) {
          // 'done'/'notListening' = сессия кончилась; финальный результат
          // может прийти следом — даём небольшую фору
          if (status == 'done' || status == 'notListening') _scheduleDone();
        },
      );
    } catch (e) {
      _available = false;
      _lastError = e.toString();
    }
    _initialized = true;
    return _available;
  }

  void _scheduleDone() {
    final cb = _onSessionDone;
    if (cb != null) Timer(const Duration(milliseconds: 450), cb);
  }

  static String _friendlyError(String? err) {
    final e = (err ?? '').toLowerCase();
    if (e.isEmpty || e.contains('no_match') || e.contains('speech_timeout')) {
      return 'Не расслышал — попробуй ещё раз, чётче и ближе к микрофону.';
    }
    if (e.contains('permission')) {
      return 'Нет разрешения на микрофон. Включи его: Настройки → Приложения → LangMe → Разрешения.';
    }
    if (e.contains('network')) {
      return 'Распознаватель требует сеть. Скачай офлайн-пакет английского: '
          'Настройки → Google → Голосовой ввод → Офлайн-распознавание.';
    }
    if (e.contains('busy')) {
      return 'Распознаватель занят — подожди секунду и попробуй ещё раз.';
    }
    if (e.contains('audio')) {
      return 'Не удалось получить звук с микрофона. Закрой другие приложения, использующие микрофон.';
    }
    return 'Ошибка распознавания: $e';
  }

  /// Слушает одну фразу. Завершается по финальному результату, паузе в речи,
  /// кнопке стоп (stopListening) или таймауту. Не бросает исключений.
  Future<SpeechAttempt> listenOnce({
    Duration timeout = const Duration(seconds: 8),
    void Function(String partial)? onPartial,
  }) async {
    if (!await init()) {
      return SpeechAttempt(
          error: 'Распознавание речи недоступно на этом устройстве. '
              '(${_friendlyError(_lastError)})');
    }

    final completer = Completer<SpeechAttempt>();
    var recognized = '';
    var confidence = -1.0;
    _lastError = null;

    void finishNow() {
      if (completer.isCompleted) return;
      _onSessionDone = null;
      if (recognized.trim().isEmpty) {
        completer.complete(SpeechAttempt(error: _friendlyError(_lastError)));
      } else {
        completer.complete(
            SpeechAttempt(recognized: recognized, confidence: confidence));
      }
    }

    _onSessionDone = finishNow;

    try {
      await _stt.listen(
        listenOptions: SpeechListenOptions(
          localeId: 'en_US',
          listenFor: timeout,
          pauseFor: const Duration(seconds: 2),
          partialResults: true,
          onDevice: false,
        ),
        onResult: (result) {
          recognized = result.recognizedWords;
          if (result.hasConfidenceRating) confidence = result.confidence;
          onPartial?.call(recognized);
          if (result.finalResult) finishNow();
        },
      );
    } catch (e) {
      _lastError = e.toString();
      finishNow();
      return completer.future;
    }

    // страховка на случай, если ни результат, ни статус не пришли
    Timer(timeout + const Duration(seconds: 4), () {
      if (!completer.isCompleted) {
        _stt.stop();
        Timer(const Duration(milliseconds: 500), finishNow);
      }
    });

    return completer.future;
  }

  /// Мгновенная остановка по кнопке: результат придёт через listenOnce.
  Future<void> stopListening() async {
    try {
      await _stt.stop();
    } catch (_) {}
  }
}
