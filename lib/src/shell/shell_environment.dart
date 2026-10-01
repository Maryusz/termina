import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../command/command_template.dart';

/// The host operating system and the shell commands are executed with.
class ShellEnvironment {
  ShellEnvironment._(
    this._wrap, {
    required this.osName,
    required this.shellName,
    required this.quoteStyle,
  });

  factory ShellEnvironment.detect() {
    if (Platform.isWindows) {
      return ShellEnvironment._(
        (c) => [
          'powershell.exe',
          '-NoLogo',
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          c,
        ],
        osName: 'Windows',
        shellName: 'PowerShell',
        quoteStyle: QuoteStyle.powershell,
      );
    }
    final String shell = Platform.environment['SHELL'] ?? '/bin/sh';
    // GUI apps on macOS start with a minimal PATH: a login shell picks up
    // Homebrew and the user's profile.
    final List<String> flags = Platform.isMacOS ? ['-l', '-c'] : ['-c'];
    return ShellEnvironment._(
      (c) => [shell, ...flags, c],
      osName: Platform.isMacOS ? 'macOS' : 'Linux',
      shellName: shell.split('/').last,
      quoteStyle: QuoteStyle.posix,
    );
  }

  final String osName;
  final String shellName;
  final QuoteStyle quoteStyle;
  final List<String> Function(String command) _wrap;

  bool get isWindows => quoteStyle == QuoteStyle.powershell;

  /// The executable and arguments that run [command] through the shell.
  List<String> argv(String command) => _wrap(command);

  String get homeDirectory =>
      Platform.environment[isWindows ? 'USERPROFILE' : 'HOME'] ??
      Directory.current.path;

  static final RegExp _executableName = RegExp(r'^[A-Za-z0-9_.+-]+$');

  /// The first word of [query] if it names an installed executable.
  Future<String?> executableIn(String query) async {
    final String first = query.trim().split(RegExp(r'\s+')).first;
    if (!_executableName.hasMatch(first)) return null;
    final String probe = isWindows
        ? 'Get-Command $first -ErrorAction Stop | Out-Null'
        : 'command -v $first';
    final ProcessResult? result = await _run(probe);
    return result != null && result.exitCode == 0 ? first : null;
  }

  /// Collects the documentation of [executable], truncated to [maxChars].
  Future<String?> helpFor(String executable, {int maxChars = 14000}) async {
    final candidates = isWindows
        ? [
            '$executable --help',
            '$executable /?',
            'Get-Help $executable | Out-String -Width 120',
          ]
        : [
            '$executable --help 2>&1',
            '$executable -h 2>&1',
            'MANPAGER=cat MANWIDTH=120 man $executable 2>/dev/null | col -bx',
          ];
    String? best;
    for (final String candidate in candidates) {
      final ProcessResult? result = await _run(candidate);
      final String out = result == null
          ? ''
          : '${result.stdout}\n${result.stderr}'.trim();
      if (out.length > (best?.length ?? 0)) best = out;
      // Short outputs are usually "unknown option" errors: try the next one.
      if (out.length > 600) break;
    }
    if (best == null || best.isEmpty) return null;
    return best.length > maxChars
        ? '${best.substring(0, maxChars)}\n…[truncated]'
        : best;
  }

  Future<ProcessResult?> _run(String command) async {
    final List<String> args = argv(command);
    try {
      final Process process = await Process.start(
        args.first,
        args.skip(1).toList(),
        environment: const {'NO_COLOR': '1', 'TERM': 'dumb'},
      );
      process.stdin.close();
      final Future<String> stdout = process.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .join();
      final Future<String> stderr = process.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .join();
      final int exitCode = await process.exitCode.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          process.kill();
          return -1;
        },
      );
      return ProcessResult(process.pid, exitCode, await stdout, await stderr);
    } on Object {
      return null;
    }
  }
}
