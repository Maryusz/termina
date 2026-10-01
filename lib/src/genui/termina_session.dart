import 'dart:async';

import 'package:genui/genui.dart';

import '../llm/llm_client.dart';
import '../shell/shell_environment.dart';
import 'reference_check.dart';

/// One generated interface: the genui conversation for a single command.
///
/// [A2uiTransportAdapter] only hands over the newest message, so the session
/// keeps the history the model needs for follow-up requests.
class TerminaSession {
  TerminaSession({
    required this._client,
    required Catalog catalog,
    required ShellEnvironment shell,
  }) : controller = SurfaceController(catalogs: [catalog]) {
    _systemPrompt = PromptBuilder.custom(
      catalog: catalog,
      allowedOperations: SurfaceOperations.all(dataModel: true),
      systemPromptFragments: [_terminaInstructions(shell)],
    ).systemPromptJoined();
    transport = A2uiTransportAdapter(onSend: _send);
    conversation = Conversation(controller: controller, transport: transport);
  }

  /// Automatic retries after the client reports invalid A2UI messages.
  static const int _maxErrorRetries = 2;

  /// Automatic requests to define components that were referenced but never
  /// sent, a frequent mistake of small local models.
  static const int _maxRepairs = 2;
  static const String _repairPrefix = 'CLIENT CHECK:';

  final LlmClient _client;
  final SurfaceController controller;
  late final A2uiTransportAdapter transport;
  late final Conversation conversation;
  late final String _systemPrompt;

  final List<LlmMessage> _history = [];
  final Set<String> _reportedErrors = {};
  int _errorRetries = 0;
  int _repairs = 0;
  bool _disposed = false;

  /// Asks the model for an interface for [query].
  Future<void> request(
    String query, {
    required String workingDirectory,
    String? executable,
    String? help,
  }) {
    final buffer = StringBuffer()
      ..writeln('Request: $query')
      ..writeln('Working directory: $workingDirectory');
    if (executable == null) {
      buffer.writeln(
        'The first word is not an installed executable: either the request is '
        'in natural language or the program must be installed first.',
      );
    } else if (help == null) {
      buffer.writeln('`$executable` is installed but printed no help.');
    } else {
      buffer
        ..writeln('`$executable` is installed. Its documentation:')
        ..writeln('<help>')
        ..writeln(help)
        ..writeln('</help>');
    }
    return conversation.sendRequest(ChatMessage.user(buffer.toString()));
  }

  /// Asks the model to change the current interface.
  Future<void> refine(String text) =>
      conversation.sendRequest(ChatMessage.user(text));

  Future<void> _send(ChatMessage message) async {
    final String errors = message.parts.uiInteractionParts
        .map((p) => p.interaction)
        .where((i) => i.contains('"error"'))
        .join('\n');
    if (errors.isNotEmpty) {
      // The Surface reports a missing component on every rebuild:
      // _checkReferences asks for all of them at once instead.
      if (errors.contains('Widget with id')) return;
      if (!_reportedErrors.add(errors)) return;
      if (_errorRetries >= _maxErrorRetries) return;
      _errorRetries++;
    } else if (message.text.isNotEmpty &&
        !message.text.startsWith(_repairPrefix)) {
      _errorRetries = 0;
      _repairs = 0;
    }

    _history.add(LlmMessage(LlmRole.user, _describe(message)));
    final reply = StringBuffer();
    try {
      await for (final String chunk in _client.stream(
        system: _systemPrompt,
        messages: List.of(_history),
      )) {
        reply.write(chunk);
        transport.addChunk(chunk);
      }
    } finally {
      if (reply.isEmpty) {
        // Keep user/assistant turns alternating so a retry starts clean.
        _history.removeLast();
      } else {
        _history.add(LlmMessage(LlmRole.assistant, reply.toString()));
        // Runs after the parser has delivered the last messages, and after
        // the conversation has finished this request.
        unawaited(Future<void>.delayed(Duration.zero, _checkReferences));
      }
    }
  }

  void _checkReferences() {
    if (_disposed || _repairs >= _maxRepairs) return;
    final problems = StringBuffer();
    for (final String surfaceId in controller.activeSurfaceIds) {
      final SurfaceDefinition? definition = controller
          .contextFor(surfaceId)
          .definition
          .value;
      if (definition == null) continue;
      findMissingReferences(definition).forEach((id, referrers) {
        problems.writeln(
          referrers.isEmpty
              ? '- surface "$surfaceId": there is no component with id "$id".'
              : '- surface "$surfaceId": component "$id" is referenced by '
                    '${referrers.map((r) => '"$r"').join(', ')} '
                    'but was never defined.',
        );
      });
    }
    if (problems.isEmpty) return;
    _repairs++;
    unawaited(
      conversation.sendRequest(
        ChatMessage.user(
          '$_repairPrefix the interface is incomplete.\n$problems'
          'Send an `updateComponents` message for the same surfaceId that '
          'defines every missing component listed above, with all required '
          'properties and bound to the data model like the other inputs. Do '
          'not create a new surface and do not resend components that are '
          'already correct.',
        ),
      ),
    );
  }

  static String _describe(ChatMessage message) {
    final buffer = StringBuffer(message.text);
    for (final UiInteractionPart part in message.parts.uiInteractionParts) {
      if (buffer.isNotEmpty) buffer.writeln();
      buffer.write('UI event from the client: ${part.interaction}');
    }
    return buffer.toString();
  }

  void dispose() {
    _disposed = true;
    conversation.dispose();
    transport.dispose();
    controller.dispose();
    _client.close();
  }
}

String _terminaInstructions(ShellEnvironment shell) =>
    '''
You are Termina, an assistant that turns terminal commands into friendly graphical interfaces, so that anyone can use the terminal without memorizing options.

The user's system is ${shell.osName}; commands are executed with ${shell.shellName}, without a TTY, in the working directory given in each request.

For every new request:
1. Create ONE surface that exposes the most useful options of the command (not all of them). Put a short `Text` intro (h3 title + one sentence) at the top. Group related options in `Card`s. Use `CheckBox` for flags, `ChoicePicker` for enumerations, `Slider` or a number `TextField` for numbers, `PathPicker` for files and directories, `TextField` for free text.
2. Initialize the data model with sensible defaults using `updateDataModel` with path "/" and an object value, so the generated command is valid immediately.
3. Add a `CommandRunner` whose template references the inputs. When the program has clearly distinct actions (e.g. git status / commit / push), use `Tabs` with one `CommandRunner` per action.
4. Write all labels and descriptions in the language of the user's request.

Rules:
- Use only options that appear in the provided documentation, or that you are certain exist for ${shell.osName}.
- If the request is in natural language, choose the most suitable command available on ${shell.osName}.
- If the program is not installed, explain it briefly and offer a `CommandRunner` with the install command for ${shell.osName}.
- Commands run without a TTY: prefer non-interactive flags (e.g. `-y`) and avoid full-screen programs (vim, top, less); offer a non-interactive alternative instead (e.g. `top -b -n 1`).
- Set `dangerous: true` on commands that delete or overwrite data, use sudo/administrator rights, or rewrite history (rm, dd, mkfs, chmod -R, git push --force, …).
- When the user asks for changes, update the existing surface with `updateComponents` / `updateDataModel` using the same surfaceId instead of creating a new one.
- Every ID used in `child`, `children`, `tabs`, `trigger` or `content` MUST be defined as a component of the same surface. Before finishing, check that every referenced ID has been defined.
- Keep prose outside the JSON blocks to one short sentence.
''';
