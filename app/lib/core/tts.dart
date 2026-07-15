import 'package:flutter_tts/flutter_tts.dart';

/// Thin wrapper around the platform TTS engine (offline on Android).
class Tts {
  static final FlutterTts _tts = FlutterTts();
  static bool _ready = false;

  static Future<void> _init() async {
    if (_ready) return;
    await _tts.setLanguage('en-US');
    _ready = true;
  }

  /// [rate] is 0..1 from settings; mapped to a comfortable engine range.
  static Future<void> speak(String text, {double rate = 0.5}) async {
    await _init();
    await _tts.stop();
    await _tts.setSpeechRate(0.25 + rate * 0.5);
    await _tts.speak(text);
  }

  static Future<void> stop() => _tts.stop();
}
