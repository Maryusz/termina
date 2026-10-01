import 'package:flutter/foundation.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:genui/genui.dart';
import 'package:json_schema_builder/json_schema_builder.dart';

final _schema = S.object(
  description: 'A text field with a button to browse for files or folders.',
  properties: {
    'label': S.string(description: 'The label shown above the field.'),
    'value': A2uiSchemas.dataBindingSchema(
      description: 'The data model path that holds the selected path(s).',
    ),
    'mode': S.string(
      description:
          'What to pick: `file` (one existing file, the default), `files` '
          '(several files, stored as a list), `directory`, or `save` (a new '
          'file name).',
      enumValues: ['file', 'files', 'directory', 'save'],
    ),
  },
  required: ['label', 'value'],
);

final pathPicker = CatalogItem(
  name: 'PathPicker',
  dataSchema: _schema,
  isImplicitlyFlexible: true,
  widgetBuilder: (itemContext) {
    final data = itemContext.data as JsonMap;
    final binding = data['value'];
    final String path = binding is Map && binding['path'] is String
        ? binding['path'] as String
        : '/${itemContext.id}';
    return _PathPicker(
      key: ValueKey('${itemContext.surfaceId}/${itemContext.id}'),
      label: data['label'] as String? ?? '',
      mode: data['mode'] as String? ?? 'file',
      path: DataPath(path),
      dataContext: itemContext.dataContext,
    );
  },
);

class _PathPicker extends StatefulWidget {
  const _PathPicker({
    super.key,
    required this.label,
    required this.mode,
    required this.path,
    required this.dataContext,
  });

  final String label;
  final String mode;
  final DataPath path;
  final DataContext dataContext;

  @override
  State<_PathPicker> createState() => _PathPickerState();
}

class _PathPickerState extends State<_PathPicker> {
  late final TextEditingController _controller;
  late final ValueListenable<Object?> _value;

  bool get _multiple => widget.mode == 'files';

  @override
  void initState() {
    super.initState();
    _value = widget.dataContext.subscribe<Object>(widget.path);
    _controller = TextEditingController(text: _format(_value.value));
    _value.addListener(_onModelChanged);
  }

  @override
  void dispose() {
    _value.removeListener(_onModelChanged);
    _controller.dispose();
    super.dispose();
  }

  String _format(Object? value) => switch (value) {
    null => '',
    Iterable<Object?> l => l.join('; '),
    _ => '$value',
  };

  void _onModelChanged() {
    final String text = _format(_value.value);
    if (text != _controller.text) _controller.text = text;
  }

  void _onTyped(String text) {
    widget.dataContext.update(
      widget.path,
      _multiple
          ? text
                .split(';')
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .toList()
          : text,
    );
  }

  Future<void> _browse() async {
    final Object? picked = switch (widget.mode) {
      'directory' => await getDirectoryPath(),
      'save' => (await getSaveLocation())?.path,
      'files' => (await openFiles()).map((f) => f.path).toList(),
      _ => (await openFile())?.path,
    };
    if (picked == null || (picked is List && picked.isEmpty)) return;
    widget.dataContext.update(widget.path, picked);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: TextField(
        controller: _controller,
        onChanged: _onTyped,
        style: const TextStyle(fontFamily: 'monospace'),
        decoration: InputDecoration(
          labelText: widget.label,
          border: const OutlineInputBorder(),
          suffixIcon: IconButton(
            tooltip: 'Sfoglia…',
            icon: Icon(
              widget.mode == 'directory' ? Icons.folder_open : Icons.file_open,
            ),
            onPressed: _browse,
          ),
        ),
      ),
    );
  }
}
