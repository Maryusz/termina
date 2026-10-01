import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'shell_environment.dart';

enum OutputKind { stdout, stderr, info }

@immutable
class OutputLine {
  const OutputLine(this.kind, this.text);

  final OutputKind kind;
  final String text;
}

/// Runs one command at a time and exposes its output to the UI.
class ProcessSession extends ChangeNotifier {
  ProcessSession(this.shell);

  final ShellEnvironment shell;

  static const int _maxLines = 5000;
  static final RegExp _ansiEscape = RegExp(
    r'\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])',
  );

  final List<OutputLine> _lines = [];
  Process? _process;
  String? _command;
  int? _exitCode;

  List<OutputLine> get lines => List.unmodifiable(_lines);
  bool get isRunning => _process != null;
  String? get command => _command;
  int? get exitCode => _exitCode;

  Future<void> run(String command, {required String workingDirectory}) async {
    if (isRunning) await stop();
    _lines.clear();
    _command = command;
    _exitCode = null;
    _add(OutputKind.info, '\$ $command');
    notifyListeners();

    final List<String> argv = shell.argv(command);
    final Process process;
    try {
      process = await Process.start(
        argv.first,
        argv.skip(1).toList(),
        workingDirectory: workingDirectory,
      );
    } on Object catch (e) {
      _add(OutputKind.stderr, 'Impossibile avviare il comando: $e');
      _exitCode = -1;
      notifyListeners();
      return;
    }
    _process = process;
    notifyListeners();

    final Encoding encoding = shell.isWindows
        ? systemEncoding
        : const Utf8Codec(allowMalformed: true);
    final Future<void> out = _pipe(process.stdout, encoding, OutputKind.stdout);
    final Future<void> err = _pipe(process.stderr, encoding, OutputKind.stderr);
    final int code = await process.exitCode;
    await Future.wait([out, err]);
    if (!identical(_process, process)) return;
    _process = null;
    _exitCode = code;
    _add(OutputKind.info, 'Processo terminato con codice $code');
    notifyListeners();
  }

  Future<void> _pipe(
    Stream<List<int>> stream,
    Encoding encoding,
    OutputKind kind,
  ) {
    return stream
        .transform(encoding.decoder)
        .transform(const LineSplitter())
        .forEach((line) {
          _add(kind, line.replaceAll(_ansiEscape, ''));
          notifyListeners();
        });
  }

  /// Sends a line to the standard input of the running process.
  void sendInput(String line) {
    final Process? process = _process;
    if (process == null) return;
    process.stdin.writeln(line);
    _add(OutputKind.info, '> $line');
    notifyListeners();
  }

  Future<void> stop() async {
    final Process? process = _process;
    if (process == null) return;
    process.kill();
    _add(OutputKind.info, 'Interrotto.');
    notifyListeners();
  }

  void clear() {
    if (isRunning) return;
    _lines.clear();
    _command = null;
    _exitCode = null;
    notifyListeners();
  }

  void _add(OutputKind kind, String text) {
    _lines.add(OutputLine(kind, text));
    if (_lines.length > _maxLines) {
      _lines.removeRange(0, _lines.length - _maxLines);
    }
  }

  @override
  void dispose() {
    _process?.kill();
    super.dispose();
  }
}
