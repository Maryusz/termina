import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genui/genui.dart';
import 'package:termina/src/catalog/termina_catalog.dart';
import 'package:termina/src/command/command_template.dart';
import 'package:termina/src/genui/termina_session.dart';
import 'package:termina/src/llm/llm_client.dart';
import 'package:termina/src/shell/shell_environment.dart';

const _reply = '''
Ecco un'interfaccia per `ls`.
```json
{"version": "v0.9", "createSurface": {"surfaceId": "ls", "catalogId": "https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json", "sendDataModel": true}}
```
```json
{"version": "v0.9", "updateDataModel": {"surfaceId": "ls", "path": "/", "value": {"all": false, "dir": "/tmp/my dir"}}}
```
```json
{"version": "v0.9", "updateComponents": {"surfaceId": "ls", "components": [
  {"id": "root", "component": "Column", "children": ["all", "run"]},
  {"id": "all", "component": "CheckBox", "label": "Mostra nascosti", "value": {"path": "/all"}},
  {"id": "run", "component": "CommandRunner", "title": "Elenca", "template": "ls -l {{/all?-a}} {{/dir}}"}
]}}
```
''';

class _FakeClient implements LlmClient {
  _FakeClient([this.replies = const [_reply]]);

  final List<String> replies;
  final List<List<LlmMessage>> calls = [];

  @override
  Stream<String> stream({
    required String system,
    required List<LlmMessage> messages,
  }) async* {
    final String reply = replies[calls.length.clamp(0, replies.length - 1)];
    calls.add(messages);
    // Split into small chunks like a real streaming response.
    for (var i = 0; i < reply.length; i += 40) {
      yield reply.substring(i, (i + 40).clamp(0, reply.length));
    }
  }

  @override
  void close() {}
}

void main() {
  testWidgets('renders a generated form and runs the bound command', (
    tester,
  ) async {
    final client = _FakeClient();
    final ran = <String>[];
    final session = TerminaSession(
      client: client,
      catalog: buildTerminaCatalog(
        quoteStyle: QuoteStyle.posix,
        onRun: (command, {required dangerous}) => ran.add(command),
      ),
      shell: ShellEnvironment.detect(),
    );
    addTearDown(session.dispose);

    final errors = <Object>[];
    session.conversation.events.listen((e) {
      if (e is ConversationError) errors.add(e.error);
    });
    // The genui streams live in the test's fake-async zone: pump them.
    final Future<void> request = session.request(
      'ls',
      workingDirectory: '/tmp',
      executable: 'ls',
    );
    for (var i = 0; i < 50; i++) {
      await tester.pump();
    }
    await request;
    expect(errors, isEmpty);

    final List<String> surfaces = session.conversation.state.value.surfaces;
    expect(surfaces, ['ls']);
    expect(client.calls.single.single.content, contains('Request: ls'));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Surface(surfaceContext: session.controller.contextFor('ls')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text("ls -l '/tmp/my dir'"), findsOneWidget);

    await tester.tap(find.text('Mostra nascosti'));
    await tester.pumpAndSettle();
    expect(find.text("ls -l -a '/tmp/my dir'"), findsOneWidget);

    await tester.tap(find.text('Esegui'));
    expect(ran, ["ls -l -a '/tmp/my dir'"]);
  });

  testWidgets('asks the model to define components it only referenced', (
    tester,
  ) async {
    const broken = '''
```json
{"version": "v0.9", "createSurface": {"surfaceId": "head", "catalogId": "https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json"}}
```
```json
{"version": "v0.9", "updateComponents": {"surfaceId": "head", "components": [
  {"id": "root", "component": "Column", "children": ["limitSlider", "run"]},
  {"id": "run", "component": "CommandRunner", "template": "head -n {{/lines}} f"}
]}}
```
''';
    const fix = '''
```json
{"version": "v0.9", "updateComponents": {"surfaceId": "head", "components": [
  {"id": "limitSlider", "component": "Slider", "label": "Righe", "min": 1, "max": 100, "value": {"path": "/lines"}}
]}}
```
''';
    final client = _FakeClient([broken, fix]);
    final session = TerminaSession(
      client: client,
      catalog: buildTerminaCatalog(
        quoteStyle: QuoteStyle.posix,
        onRun: (command, {required dangerous}) {},
      ),
      shell: ShellEnvironment.detect(),
    );
    addTearDown(session.dispose);

    unawaited(session.request('head', workingDirectory: '/tmp'));
    for (var i = 0; i < 100; i++) {
      await tester.pump(const Duration(milliseconds: 1));
    }

    expect(client.calls, hasLength(2));
    final String repair = client.calls.last.last.content;
    expect(repair, contains('"limitSlider" is referenced by "root"'));
    expect(client.calls.last, hasLength(3), reason: 'keeps the history');

    final SurfaceDefinition definition = session.controller
        .contextFor('head')
        .definition
        .value!;
    expect(definition.components.keys, contains('limitSlider'));
  });
}
