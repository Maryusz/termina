import 'package:flutter/material.dart';

import '../settings/settings.dart';

/// Edits the model provider settings. Returns the new settings, if saved.
Future<TerminaSettings?> showSettingsDialog(
  BuildContext context,
  TerminaSettings initial,
) {
  return showDialog<TerminaSettings>(
    context: context,
    builder: (context) => _SettingsDialog(initial: initial),
  );
}

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog({required this.initial});

  final TerminaSettings initial;

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  late LlmProvider _provider = widget.initial.provider;
  late String _effort = widget.initial.effort;
  late final _anthropicKey = TextEditingController(
    text: widget.initial.anthropicApiKey,
  );
  late final _anthropicModel = TextEditingController(
    text: widget.initial.anthropicModel,
  );
  late final _geminiKey = TextEditingController(
    text: widget.initial.geminiApiKey,
  );
  late final _geminiModel = TextEditingController(
    text: widget.initial.geminiModel,
  );
  late final _openAiBaseUrl = TextEditingController(
    text: widget.initial.openAiBaseUrl,
  );
  late final _openAiModel = TextEditingController(
    text: widget.initial.openAiModel,
  );
  late final _openAiKey = TextEditingController(
    text: widget.initial.openAiApiKey,
  );

  @override
  void dispose() {
    for (final c in [
      _anthropicKey,
      _anthropicModel,
      _geminiKey,
      _geminiModel,
      _openAiBaseUrl,
      _openAiModel,
      _openAiKey,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  TerminaSettings get _result => widget.initial.copyWith(
    provider: _provider,
    effort: _effort,
    anthropicApiKey: _anthropicKey.text.trim(),
    anthropicModel: _anthropicModel.text.trim(),
    geminiApiKey: _geminiKey.text.trim(),
    geminiModel: _geminiModel.text.trim(),
    openAiBaseUrl: _openAiBaseUrl.text.trim(),
    openAiModel: _openAiModel.text.trim(),
    openAiApiKey: _openAiKey.text.trim(),
  );

  Widget _effortField() => DropdownButtonFormField<String>(
    initialValue: _effort,
    decoration: const InputDecoration(
      labelText: 'Ragionamento (velocità ↔ qualità)',
      border: OutlineInputBorder(),
    ),
    items: const [
      DropdownMenuItem(value: 'low', child: Text('low')),
      DropdownMenuItem(value: 'medium', child: Text('medium')),
      DropdownMenuItem(value: 'high', child: Text('high')),
    ],
    onChanged: (v) => setState(() => _effort = v ?? _effort),
  );

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 12);
    return AlertDialog(
      title: const Text('Impostazioni modello'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<LlmProvider>(
                segments: const [
                  ButtonSegment(
                    value: LlmProvider.anthropic,
                    label: Text('Claude'),
                  ),
                  ButtonSegment(
                    value: LlmProvider.gemini,
                    label: Text('Gemini'),
                  ),
                  ButtonSegment(
                    value: LlmProvider.openAiCompatible,
                    label: Text('OpenAI / Ollama'),
                  ),
                ],
                selected: {_provider},
                onSelectionChanged: (s) => setState(() => _provider = s.first),
              ),
              gap,
              if (_provider == LlmProvider.anthropic) ...[
                TextField(
                  controller: _anthropicKey,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'API key Anthropic',
                    helperText: 'Vuota: usa la variabile ANTHROPIC_API_KEY',
                    border: OutlineInputBorder(),
                  ),
                ),
                gap,
                TextField(
                  controller: _anthropicModel,
                  decoration: const InputDecoration(
                    labelText: 'Modello',
                    border: OutlineInputBorder(),
                  ),
                ),
                gap,
                _effortField(),
              ],
              if (_provider == LlmProvider.gemini) ...[
                TextField(
                  controller: _geminiKey,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'API key Google AI Studio',
                    helperText:
                        'Vuota: usa GEMINI_API_KEY o GOOGLE_API_KEY. '
                        'Creala su aistudio.google.com/apikey',
                    border: OutlineInputBorder(),
                  ),
                ),
                gap,
                TextField(
                  controller: _geminiModel,
                  decoration: const InputDecoration(
                    labelText: 'Modello',
                    border: OutlineInputBorder(),
                  ),
                ),
                gap,
                _effortField(),
              ],
              if (_provider == LlmProvider.openAiCompatible) ...[
                TextField(
                  controller: _openAiBaseUrl,
                  decoration: const InputDecoration(
                    labelText: 'Base URL',
                    helperText: 'Es. http://localhost:11434/v1 per Ollama',
                    border: OutlineInputBorder(),
                  ),
                ),
                gap,
                TextField(
                  controller: _openAiModel,
                  decoration: const InputDecoration(
                    labelText: 'Modello',
                    border: OutlineInputBorder(),
                  ),
                ),
                gap,
                TextField(
                  controller: _openAiKey,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'API key (opzionale)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annulla'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _result),
          child: const Text('Salva'),
        ),
      ],
    );
  }
}
