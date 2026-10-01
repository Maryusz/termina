import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

enum LlmRole { user, assistant }

class LlmMessage {
  const LlmMessage(this.role, this.content);

  final LlmRole role;
  final String content;
}

class LlmException implements Exception {
  const LlmException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Streams the text of a model reply.
abstract interface class LlmClient {
  Stream<String> stream({
    required String system,
    required List<LlmMessage> messages,
  });

  void close();
}

/// Reads `data:` payloads from a Server-Sent Events response.
Stream<String> _sseData(http.StreamedResponse response) => response.stream
    .transform(utf8.decoder)
    .transform(const LineSplitter())
    .where((line) => line.startsWith('data:'))
    .map((line) => line.substring(5).trim());

Future<Never> _throwHttpError(http.StreamedResponse response) async {
  final String body = await response.stream.bytesToString();
  var message = body;
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map && decoded['error'] is Map) {
      message = '${(decoded['error'] as Map)['message']}';
    }
  } on FormatException {
    // Not JSON: keep the raw body.
  }
  throw LlmException('HTTP ${response.statusCode}: $message');
}

/// Claude via the Anthropic Messages API (raw HTTP: there is no Dart SDK).
class AnthropicClient implements LlmClient {
  AnthropicClient({
    required this.apiKey,
    this.model = defaultModel,
    this.effort = 'medium',
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  static const String defaultModel = 'claude-opus-5-5';

  /// Models that accept the server-side refusal fallback.
  static const Set<String> _fallbackModels = {
    'claude-fable-5-1',
    'claude-opus-5-5',
    'claude-opus-5',
    'claude-sonnet-5-5',
  };

  final String apiKey;
  final String model;
  final String effort;
  final http.Client _http;

  @override
  Stream<String> stream({
    required String system,
    required List<LlmMessage> messages,
  }) async* {
    final bool fallbacks = _fallbackModels.contains(model);
    final request =
        http.Request('POST', Uri.parse('https://api.anthropic.com/v1/messages'))
          ..headers.addAll({
            'content-type': 'application/json',
            'x-api-key': apiKey,
            'anthropic-version': '2023-06-01',
            if (fallbacks) 'anthropic-beta': 'server-side-fallback-2026-07-01',
          })
          ..body = jsonEncode({
            'model': model,
            'max_tokens': 64000,
            'stream': true,
            'output_config': {'effort': effort},
            if (fallbacks) 'fallbacks': 'default',
            // The system prompt embeds the whole A2UI schema: cache it.
            'system': [
              {
                'type': 'text',
                'text': system,
                'cache_control': {'type': 'ephemeral'},
              },
            ],
            'messages': [
              for (final m in messages)
                {'role': m.role.name, 'content': m.content},
            ],
          });

    final http.StreamedResponse response = await _http.send(request);
    if (response.statusCode != 200) await _throwHttpError(response);

    await for (final String data in _sseData(response)) {
      final event = jsonDecode(data) as Map<String, Object?>;
      switch (event['type']) {
        case 'content_block_delta':
          final delta = event['delta'] as Map<String, Object?>;
          if (delta['type'] == 'text_delta') yield delta['text'] as String;
        case 'message_delta':
          final delta = event['delta'] as Map<String, Object?>;
          if (delta['stop_reason'] == 'refusal') {
            throw const LlmException('Il modello ha rifiutato la richiesta.');
          }
        case 'error':
          final error = event['error'] as Map<String, Object?>?;
          throw LlmException('${error?['message'] ?? data}');
      }
    }
  }

  @override
  void close() => _http.close();
}

/// Gemini via the Google AI Studio (Gemini API) REST endpoint.
class GeminiClient implements LlmClient {
  GeminiClient({
    required this.apiKey,
    this.model = defaultModel,
    this.thinkingLevel = 'medium',
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  static const String defaultModel = 'gemini-3.8-flash';

  final String apiKey;
  final String model;

  /// `low`, `medium` or `high`.
  final String thinkingLevel;
  final http.Client _http;

  @override
  Stream<String> stream({
    required String system,
    required List<LlmMessage> messages,
  }) async* {
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/'
      '$model:streamGenerateContent?alt=sse',
    );
    final request = http.Request('POST', uri)
      ..headers.addAll({
        'content-type': 'application/json',
        'x-goog-api-key': apiKey,
      })
      ..body = jsonEncode({
        'systemInstruction': {
          'parts': [
            {'text': system},
          ],
        },
        'contents': [
          for (final m in messages)
            {
              'role': m.role == LlmRole.user ? 'user' : 'model',
              'parts': [
                {'text': m.content},
              ],
            },
        ],
        'generationConfig': {
          'thinkingConfig': {'thinkingLevel': thinkingLevel},
        },
      });

    final http.StreamedResponse response = await _http.send(request);
    if (response.statusCode != 200) await _throwHttpError(response);

    await for (final String data in _sseData(response)) {
      final event = jsonDecode(data) as Map<String, Object?>;
      final feedback = event['promptFeedback'] as Map<String, Object?>?;
      if (feedback?['blockReason'] != null) {
        throw LlmException('Richiesta bloccata: ${feedback!['blockReason']}');
      }
      final candidates = event['candidates'] as List<Object?>?;
      if (candidates == null || candidates.isEmpty) continue;
      final candidate = candidates.first as Map<String, Object?>;
      final content = candidate['content'] as Map<String, Object?>?;
      for (final Object? part in content?['parts'] as List<Object?>? ?? []) {
        if (part is! Map || part['thought'] == true) continue;
        final text = part['text'];
        if (text is String && text.isNotEmpty) yield text;
      }
      final finish = candidate['finishReason'];
      if (finish == 'SAFETY' || finish == 'PROHIBITED_CONTENT') {
        throw LlmException('Risposta interrotta dal modello: $finish');
      }
    }
  }

  @override
  void close() => _http.close();
}

/// Any OpenAI-compatible chat completions endpoint (Ollama, LM Studio, …).
class OpenAiCompatibleClient implements LlmClient {
  OpenAiCompatibleClient({
    required this.baseUrl,
    required this.model,
    this.apiKey = '',
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final String baseUrl;
  final String model;
  final String apiKey;
  final http.Client _http;

  @override
  Stream<String> stream({
    required String system,
    required List<LlmMessage> messages,
  }) async* {
    final String base = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final request = http.Request('POST', Uri.parse('$base/chat/completions'))
      ..headers.addAll({
        'content-type': 'application/json',
        if (apiKey.isNotEmpty) 'authorization': 'Bearer $apiKey',
      })
      ..body = jsonEncode({
        'model': model,
        'stream': true,
        'messages': [
          {'role': 'system', 'content': system},
          for (final m in messages) {'role': m.role.name, 'content': m.content},
        ],
      });

    final http.StreamedResponse response = await _http.send(request);
    if (response.statusCode != 200) await _throwHttpError(response);

    await for (final String data in _sseData(response)) {
      if (data == '[DONE]') break;
      final event = jsonDecode(data) as Map<String, Object?>;
      final choices = event['choices'] as List<Object?>?;
      if (choices == null || choices.isEmpty) continue;
      final delta = (choices.first as Map)['delta'] as Map<String, Object?>?;
      final content = delta?['content'];
      if (content is String && content.isNotEmpty) yield content;
    }
  }

  @override
  void close() => _http.close();
}
