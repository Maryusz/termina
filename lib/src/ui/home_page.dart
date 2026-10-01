import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:genui/genui.dart';

import '../catalog/termina_catalog.dart';
import '../genui/termina_session.dart';
import '../settings/settings.dart';
import '../shell/process_session.dart';
import '../shell/shell_environment.dart';
import 'output_console.dart';
import 'settings_dialog.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.initialSettings});

  final TerminaSettings initialSettings;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const List<String> _suggestions = [
    'tar',
    'find',
    'ffmpeg',
    'git log',
    'rsync',
    'converti un video in gif',
    'trova i file più grandi nella cartella',
    'mostra i processi che usano più memoria',
  ];

  final ShellEnvironment _shell = ShellEnvironment.detect();
  late final ProcessSession _process = ProcessSession(_shell);
  final TextEditingController _input = TextEditingController();
  final FocusNode _inputFocus = FocusNode();

  late TerminaSettings _settings = widget.initialSettings;
  late String _workingDirectory = _shell.homeDirectory;

  TerminaSession? _session;
  StreamSubscription<ConversationEvent>? _events;
  String? _title;
  String _status = '';
  bool _preparing = false;

  @override
  void dispose() {
    _events?.cancel();
    _session?.dispose();
    _process.dispose();
    _input.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final String text = _input.text.trim();
    if (text.isEmpty || _preparing) return;
    if (!_settings.isConfigured) {
      await _openSettings();
      if (!_settings.isConfigured) return;
    }
    _input.clear();
    final TerminaSession? session = _session;
    if (session != null) {
      unawaited(session.refine(text));
      return;
    }
    await _startSession(text);
  }

  Future<void> _startSession(String query) async {
    setState(() {
      _preparing = true;
      _title = query;
      _status = 'Leggo la documentazione…';
    });
    final String? executable = await _shell.executableIn(query);
    final String? help = executable == null
        ? null
        : await _shell.helpFor(executable);
    if (!mounted) return;

    final session = TerminaSession(
      client: _settings.createClient(),
      catalog: buildTerminaCatalog(
        quoteStyle: _shell.quoteStyle,
        onRun: _runCommand,
      ),
      shell: _shell,
    );
    _events = session.conversation.events.listen(_onEvent);
    setState(() {
      _session = session;
      _preparing = false;
      _status = 'Genero l\'interfaccia…';
    });
    unawaited(
      session.request(
        query,
        workingDirectory: _workingDirectory,
        executable: executable,
        help: help,
      ),
    );
  }

  void _onEvent(ConversationEvent event) {
    switch (event) {
      case ConversationContentReceived(:final text):
        final String line = text.trim();
        if (line.isNotEmpty) setState(() => _status = line);
      case ConversationError(:final error):
        setState(() => _status = '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Errore: $error'),
            duration: const Duration(seconds: 8),
          ),
        );
      case ConversationSurfaceAdded() ||
          ConversationSurfaceRemoved() ||
          ConversationComponentsUpdated() ||
          ConversationWaiting():
        break;
    }
  }

  void _reset() {
    _events?.cancel();
    _session?.dispose();
    setState(() {
      _events = null;
      _session = null;
      _title = null;
      _status = '';
    });
    _inputFocus.requestFocus();
  }

  Future<void> _runCommand(String command, {required bool dangerous}) async {
    if (dangerous) {
      final bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.warning_amber),
          title: const Text('Comando potenzialmente pericoloso'),
          content: SelectableText(
            command,
            style: const TextStyle(fontFamily: 'monospace'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Esegui comunque'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    unawaited(_process.run(command, workingDirectory: _workingDirectory));
  }

  Future<void> _pickWorkingDirectory() async {
    final String? dir = await getDirectoryPath(
      initialDirectory: _workingDirectory,
    );
    if (dir != null) setState(() => _workingDirectory = dir);
  }

  Future<void> _openSettings() async {
    final TerminaSettings? updated = await showSettingsDialog(
      context,
      _settings,
    );
    if (updated == null) return;
    await updated.save();
    setState(() => _settings = updated);
  }

  @override
  Widget build(BuildContext context) {
    final Widget generated = _buildGeneratedArea(context);
    final Widget console = OutputConsole(session: _process);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Termina'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: ActionChip(
              avatar: const Icon(Icons.folder, size: 18),
              label: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 280),
                child: Text(
                  _workingDirectory,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ),
              tooltip: 'Cartella di lavoro',
              onPressed: _pickWorkingDirectory,
            ),
          ),
          IconButton(
            tooltip: 'Impostazioni',
            icon: const Icon(Icons.settings),
            onPressed: _openSettings,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 1100) {
            return Row(
              children: [
                Expanded(flex: 3, child: generated),
                const VerticalDivider(width: 1),
                Expanded(flex: 2, child: console),
              ],
            );
          }
          return Column(
            children: [
              Expanded(child: generated),
              const Divider(height: 1),
              SizedBox(height: constraints.maxHeight * 0.35, child: console),
            ],
          );
        },
      ),
    );
  }

  Widget _buildGeneratedArea(BuildContext context) {
    final TerminaSession? session = _session;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildPromptBar(context),
        if (session == null && !_preparing)
          Expanded(child: _buildWelcome(context))
        else
          Expanded(
            child: session == null
                ? _buildProgress(context)
                : ValueListenableBuilder<ConversationState>(
                    valueListenable: session.conversation.state,
                    builder: (context, state, _) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (state.isWaiting) const LinearProgressIndicator(),
                          if (state.surfaces.isEmpty)
                            Expanded(
                              child: state.isWaiting
                                  ? _buildProgress(context)
                                  : const Center(
                                      child: Text('Nessuna interfaccia.'),
                                    ),
                            )
                          else
                            Expanded(
                              child: ListView(
                                padding: const EdgeInsets.all(16),
                                children: [
                                  for (final String id in state.surfaces)
                                    Surface(
                                      key: ValueKey(id),
                                      surfaceContext: session.controller
                                          .contextFor(id),
                                    ),
                                ],
                              ),
                            ),
                        ],
                      );
                    },
                  ),
          ),
      ],
    );
  }

  Widget _buildPromptBar(BuildContext context) {
    final bool hasSession = _session != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          if (hasSession) ...[
            IconButton.filledTonal(
              tooltip: 'Nuovo comando',
              icon: const Icon(Icons.add),
              onPressed: _reset,
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: TextField(
              controller: _input,
              focusNode: _inputFocus,
              autofocus: true,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.terminal),
                hintText: hasSession
                    ? 'Chiedi una modifica a "$_title" (es. aggiungi l\'opzione per escludere file)'
                    : 'Quale comando vuoi usare? (es. tar, ffmpeg, "trova file duplicati")',
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _preparing ? null : _submit,
            icon: const Icon(Icons.auto_awesome),
            label: Text(hasSession ? 'Modifica' : 'Genera'),
          ),
        ],
      ),
    );
  }

  Widget _buildProgress(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(_status, textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildWelcome(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.terminal, size: 64, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text(
                'Il terminale, senza memorizzare nulla',
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Scrivi un comando o descrivi cosa vuoi fare: Termina legge la '
                'documentazione del programma e genera un\'interfaccia grafica '
                'su misura per ${_shell.osName}.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final String s in _suggestions)
                    ActionChip(
                      label: Text(s),
                      onPressed: () {
                        _input.text = s;
                        _submit();
                      },
                    ),
                ],
              ),
              if (!_settings.isConfigured) ...[
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: _openSettings,
                  icon: const Icon(Icons.key),
                  label: const Text('Configura il modello AI'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
