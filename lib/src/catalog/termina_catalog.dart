import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:genui/genui.dart';
import 'package:json_schema_builder/json_schema_builder.dart';

import '../command/command_template.dart';
import 'path_picker.dart';

/// Called when the user presses "Esegui" on a generated command.
typedef RunCommandCallback = void Function(
  String command, {
  required bool dangerous,
});

/// The basic genui catalog plus the Termina-specific components.
Catalog buildTerminaCatalog({
  required QuoteStyle quoteStyle,
  required RunCommandCallback onRun,
}) {
  return BasicCatalogItems.asNoAssetCatalog().copyWith(
    newItems: [
      _commandRunner(quoteStyle: quoteStyle, onRun: onRun),
      pathPicker,
    ],
    systemPromptFragments: [
      ...BasicCatalogItems.asNoAssetCatalog().systemPromptFragments,
      terminaCatalogRules,
    ],
  );
}

const String terminaCatalogRules = r'''
**TERMINA COMPONENTS:**
- `CommandRunner` is the ONLY way to execute a command. Never use a `Button` to run a command.
  Its `template` is the full command line with placeholders bound to the data model:
  - `{{/path}}` inserts the value at `/path` (automatically shell-quoted; empty values and `false` disappear; lists insert every element).
  - `{{/path?text}}` inserts `text` only when the value at `/path` is truthy (non-empty string, true, non-zero number, non-empty list). Inside `text`, `%s` is replaced by the quoted value, e.g. `{{/lines?-n %s}}`.
  - `{{!/path?text}}` inserts `text` only when the value is falsy.
  Never write quotes around placeholders: quoting is automatic.
  Example: `tar {{/compress?-z}} -c -f {{/archive}} {{/sources}}`.
- `PathPicker` lets the user type or browse for a file or directory. Bind `value` to a data model path, e.g. `{"path": "/input"}`, and set `mode` to `file`, `files`, `directory` or `save`.
- Bind every input (TextField, CheckBox, ChoicePicker, Slider, PathPicker) to an absolute data model path such as `/flags/verbose`, and reference the same paths in the `CommandRunner` template.
''';

final _commandRunnerSchema = S.object(
  description:
      'Shows the command line built from the form, live, with buttons to '
      'copy and run it in the terminal.',
  properties: {
    'template': S.string(
      description:
          'The command line with {{/path}}, {{/path?text}} and '
          '{{!/path?text}} placeholders bound to the data model.',
    ),
    'title': S.string(description: 'Short title, e.g. "Comprimi cartella".'),
    'description': S.string(
      description: 'One sentence explaining what the command does.',
    ),
    'dangerous': S.boolean(
      description:
          'True when the command deletes or overwrites data, changes system '
          'settings or needs elevated privileges. Asks for confirmation.',
    ),
  },
  required: ['template'],
);

CatalogItem _commandRunner({
  required QuoteStyle quoteStyle,
  required RunCommandCallback onRun,
}) {
  return CatalogItem(
    name: 'CommandRunner',
    dataSchema: _commandRunnerSchema,
    widgetBuilder: (itemContext) {
      final data = itemContext.data as JsonMap;
      return _CommandRunnerCard(
        template: CommandTemplate(data['template'] as String? ?? ''),
        title: data['title'] as String?,
        description: data['description'] as String?,
        dangerous: data['dangerous'] == true,
        dataContext: itemContext.dataContext,
        quoteStyle: quoteStyle,
        onRun: onRun,
      );
    },
    exampleData: [
      () => '''
      [
        {"id": "root", "component": "Column", "children": ["dir", "all", "run"]},
        {"id": "dir", "component": "PathPicker", "label": "Cartella", "mode": "directory", "value": {"path": "/dir"}},
        {"id": "all", "component": "CheckBox", "label": "Mostra file nascosti", "value": {"path": "/all"}},
        {"id": "run", "component": "CommandRunner", "title": "Elenca file", "template": "ls -l {{/all?-a}} {{/dir}}"}
      ]
    ''',
    ],
  );
}

class _CommandRunnerCard extends StatefulWidget {
  const _CommandRunnerCard({
    required this.template,
    required this.title,
    required this.description,
    required this.dangerous,
    required this.dataContext,
    required this.quoteStyle,
    required this.onRun,
  });

  final CommandTemplate template;
  final String? title;
  final String? description;
  final bool dangerous;
  final DataContext dataContext;
  final QuoteStyle quoteStyle;
  final RunCommandCallback onRun;

  @override
  State<_CommandRunnerCard> createState() => _CommandRunnerCardState();
}

class _CommandRunnerCardState extends State<_CommandRunnerCard> {
  late Listenable _changes;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(_CommandRunnerCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.template.source != widget.template.source ||
        oldWidget.dataContext != widget.dataContext) {
      _subscribe();
    }
  }

  void _subscribe() {
    _changes = Listenable.merge([
      for (final String path in widget.template.paths)
        widget.dataContext.subscribe<Object>(DataPath(path)),
    ]);
  }

  String _render() => widget.template.render(
    (path) => widget.dataContext.getValue<Object>(DataPath(path)),
    style: widget.quoteStyle,
  );

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final String? title = widget.title;
    final String? description = widget.description;
    final bool dangerous = widget.dangerous;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      color: colors.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ListenableBuilder(
          listenable: _changes,
          builder: (context, _) {
            final String command = _render();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(
                      dangerous ? Icons.warning_amber : Icons.terminal,
                      color: dangerous ? colors.error : colors.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title ?? 'Comando',
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
                if (description != null) ...[
                  const SizedBox(height: 4),
                  Text(description, style: theme.textTheme.bodySmall),
                ],
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    command,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: command.isEmpty
                          ? null
                          : () {
                              Clipboard.setData(ClipboardData(text: command));
                              ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                                const SnackBar(
                                  content: Text('Comando copiato'),
                                ),
                              );
                            },
                      icon: const Icon(Icons.copy),
                      label: const Text('Copia'),
                    ),
                    FilledButton.icon(
                      style: dangerous
                          ? FilledButton.styleFrom(
                              backgroundColor: colors.error,
                              foregroundColor: colors.onError,
                            )
                          : null,
                      onPressed: command.isEmpty
                          ? null
                          : () => widget.onRun(command, dangerous: dangerous),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Esegui'),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
