import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../shell/process_session.dart';

/// Shows the output of the running command, with stop and stdin controls.
class OutputConsole extends StatefulWidget {
  const OutputConsole({super.key, required this.session});

  final ProcessSession session;

  @override
  State<OutputConsole> createState() => _OutputConsoleState();
}

class _OutputConsoleState extends State<OutputConsole> {
  final _scroll = ScrollController();
  final _input = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_followTail);
  }

  @override
  void dispose() {
    widget.session.removeListener(_followTail);
    _scroll.dispose();
    _input.dispose();
    super.dispose();
  }

  void _followTail() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  void _sendInput() {
    widget.session.sendInput(_input.text);
    _input.clear();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: widget.session,
      builder: (context, _) {
        final ProcessSession session = widget.session;
        final int? exitCode = session.exitCode;
        return Material(
          color: colors.surfaceContainerLowest,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                child: Row(
                  children: [
                    Icon(
                      session.isRunning
                          ? Icons.hourglass_top
                          : exitCode == null
                          ? Icons.terminal
                          : exitCode == 0
                          ? Icons.check_circle
                          : Icons.error,
                      size: 18,
                      color: exitCode != null && exitCode != 0
                          ? colors.error
                          : colors.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        session.command ?? 'Output',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                    ),
                    if (session.isRunning)
                      IconButton(
                        tooltip: 'Interrompi',
                        icon: const Icon(Icons.stop),
                        onPressed: session.stop,
                      ),
                    IconButton(
                      tooltip: 'Copia output',
                      icon: const Icon(Icons.copy_all),
                      onPressed: session.lines.isEmpty
                          ? null
                          : () => Clipboard.setData(
                              ClipboardData(
                                text: session.lines
                                    .map((l) => l.text)
                                    .join('\n'),
                              ),
                            ),
                    ),
                    IconButton(
                      tooltip: 'Pulisci',
                      icon: const Icon(Icons.clear_all),
                      onPressed: session.isRunning ? null : session.clear,
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: session.lines.isEmpty
                    ? Center(
                        child: Text(
                          'L\'output dei comandi apparirà qui',
                          style: TextStyle(color: colors.outline),
                        ),
                      )
                    : SelectionArea(
                        child: ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.all(12),
                          itemCount: session.lines.length,
                          itemBuilder: (context, index) {
                            final OutputLine line = session.lines[index];
                            return Text(
                              line.text,
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 13,
                                color: switch (line.kind) {
                                  OutputKind.stdout => colors.onSurface,
                                  OutputKind.stderr => colors.error,
                                  OutputKind.info => colors.primary,
                                },
                              ),
                            );
                          },
                        ),
                      ),
              ),
              if (session.isRunning)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: TextField(
                    controller: _input,
                    onSubmitted: (_) => _sendInput(),
                    style: const TextStyle(fontFamily: 'monospace'),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Invia input al processo…',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.keyboard_return),
                        onPressed: _sendInput,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
