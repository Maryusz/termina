import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:termina/src/llm/llm_client.dart';

void main() {
  test('streams Gemini text, skipping thoughts', () async {
    late http.Request sent;
    final mock = MockClient.streaming((request, body) async {
      sent = request as http.Request;
      const sse =
          'data: {"candidates":[{"content":{"role":"model","parts":[{"text":"pensiero","thought":true}]}}]}\n\n'
          'data: {"candidates":[{"content":{"role":"model","parts":[{"text":"Ciao "}]}}]}\n\n'
          'data: {"candidates":[{"content":{"role":"model","parts":[{"text":"mondo"}]},"finishReason":"STOP"}]}\n\n';
      return http.StreamedResponse(Stream.value(utf8.encode(sse)), 200);
    });
    final client = GeminiClient(apiKey: 'k', httpClient: mock);

    final List<String> chunks = await client
        .stream(
          system: 'sys',
          messages: const [
            LlmMessage(LlmRole.user, 'ls'),
            LlmMessage(LlmRole.assistant, 'ok'),
            LlmMessage(LlmRole.user, 'altro'),
          ],
        )
        .toList();

    expect(chunks, ['Ciao ', 'mondo']);
    expect(
      sent.url.path,
      '/v1beta/models/gemini-3.8-flash:streamGenerateContent',
    );
    expect(sent.headers['x-goog-api-key'], 'k');
    final body = jsonDecode(sent.body) as Map<String, Object?>;
    expect((body['contents'] as List).map((c) => (c as Map)['role']), [
      'user',
      'model',
      'user',
    ]);
    expect(body['generationConfig'], {
      'thinkingConfig': {'thinkingLevel': 'medium'},
    });
  });

  test('reports HTTP errors with the API message', () {
    final mock = MockClient(
      (_) async => http.Response(
        '{"error":{"code":400,"message":"API key not valid"}}',
        400,
      ),
    );
    final client = GeminiClient(apiKey: 'bad', httpClient: mock);
    expect(
      client.stream(system: 's', messages: const []).toList(),
      throwsA(
        isA<LlmException>().having(
          (e) => e.message,
          'message',
          contains('API key not valid'),
        ),
      ),
    );
  });
}
