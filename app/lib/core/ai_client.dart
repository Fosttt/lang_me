import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'ai_config.dart';
import 'db.dart';

/// Client for the personal LLM proxy (server/ in this repo, runs on my VPS
/// on top of `claude -p --model haiku`). Explain/examples responses are
/// cached locally so a repeated tap works offline and saves quota.
class AiClient {
  final String baseUrl;
  final String token;

  AiClient({required this.baseUrl, required this.token});

  /// Shared client with certificate pinning: for https the app trusts ONLY
  /// the certificate whose SHA-256 (DER) matches [kAiCertSha256].
  static final http.Client _http = _makeClient();

  static http.Client _makeClient() {
    if (kAiCertSha256.isEmpty) return http.Client();
    final inner = HttpClient()
      ..badCertificateCallback = (X509Certificate cert, String host, int port) =>
          sha256.convert(cert.der).toString() == kAiCertSha256.toLowerCase();
    return IOClient(inner);
  }

  Uri _u(String path) =>
      Uri.parse('${baseUrl.replaceAll(RegExp(r'/+$'), '')}$path');

  Future<String> _post(String path, Map<String, dynamic> body,
      {Duration timeout = const Duration(seconds: 90)}) async {
    final resp = await _http
        .post(
          _u(path),
          headers: {
            'Content-Type': 'application/json',
            'X-Auth-Token': token,
          },
          body: jsonEncode(body),
        )
        .timeout(timeout);
    if (resp.statusCode == 401) {
      throw AiError('Неверный токен (401). Проверьте настройки.');
    }
    if (resp.statusCode == 429) {
      throw AiError('Сервер занят другим запросом (429). Повторите чуть позже.');
    }
    if (resp.statusCode == 504) {
      throw AiError('LLM не ответил вовремя (504). Повторите позже.');
    }
    if (resp.statusCode != 200) {
      throw AiError('Ошибка сервера: HTTP ${resp.statusCode}');
    }
    final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    return (data['text'] ?? '') as String;
  }

  Future<bool> health() async {
    try {
      final resp = await _http
          .get(_u('/health'), headers: {'X-Auth-Token': token})
          .timeout(const Duration(seconds: 10));
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Cached: explain the word differently.
  Future<String> explain(String word, String ru) async {
    final key = 'explain:$word';
    final cached = await AppDb.cacheGet(key);
    if (cached != null) return cached;
    final text = await _post('/llm/explain', {'word': word, 'ru': ru});
    await AppDb.cachePut(key, text);
    return text;
  }

  /// Cached: extra example sentences.
  Future<String> examples(String word, String ru) async {
    final key = 'examples:$word';
    final cached = await AppDb.cacheGet(key);
    if (cached != null) return cached;
    final text = await _post('/llm/examples', {'word': word, 'ru': ru});
    await AppDb.cachePut(key, text);
    return text;
  }

  /// Not cached: check the user's own sentence with the word.
  Future<String> check(String word, String sentence) =>
      _post('/llm/check', {'word': word, 'sentence': sentence});

  /// Not cached: tutor chat. [recentWords] are woven into the conversation.
  Future<String> chat(List<Map<String, String>> history,
          List<String> recentWords) =>
      _post('/llm/chat', {'history': history, 'recent_words': recentWords},
          timeout: const Duration(seconds: 120));
}

class AiError implements Exception {
  final String message;
  AiError(this.message);
  @override
  String toString() => message;
}
