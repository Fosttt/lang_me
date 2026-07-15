import 'package:flutter_tts/flutter_tts.dart';

/// Thin wrapper around the platform TTS engine (offline on Android).
/// Dialogue speakers get different pitches so A and B sound distinct.
class Tts {
  static final FlutterTts _tts = FlutterTts();
  static bool _ready = false;
  static int _seq = 0; // generation counter to cancel sequential playback

  static const double pitchA = 1.15;
  static const double pitchB = 0.85;

  static Future<void> _init() async {
    if (_ready) return;
    await _tts.setLanguage('en-US');
    await _tts.awaitSpeakCompletion(true);
    _ready = true;
  }

  /// [rate] is 0..1 from settings; mapped to a comfortable engine range.
  static Future<void> speak(String text,
      {double rate = 0.5, double pitch = 1.0}) async {
    await _init();
    _seq++;
    await _tts.stop();
    await _tts.setSpeechRate(0.25 + rate * 0.5);
    await _tts.setPitch(pitch);
    await _tts.speak(text);
  }

  /// Speaks [parts] one after another; each item is (text, pitch).
  /// [onLine] fires before each line (for highlighting). A later speak()/
  /// speakSeq()/stop() call cancels the rest of the sequence.
  static Future<void> speakSeq(
    List<(String, double)> parts, {
    double rate = 0.5,
    void Function(int index)? onLine,
  }) async {
    await _init();
    final my = ++_seq;
    await _tts.stop();
    await _tts.setSpeechRate(0.25 + rate * 0.5);
    for (var i = 0; i < parts.length; i++) {
      if (_seq != my) return; // cancelled
      onLine?.call(i);
      await _tts.setPitch(parts[i].$2);
      await _tts.speak(parts[i].$1); // awaits completion
      await Future.delayed(const Duration(milliseconds: 250));
    }
    if (_seq == my) onLine?.call(-1); // finished
  }

  static Future<void> stop() {
    _seq++;
    return _tts.stop();
  }
}
