import 'package:genui/genui.dart';

/// Finds component IDs that [definition] references but never defines.
///
/// Returns, for each missing ID, the IDs of the components referencing it.
/// A missing `root` is reported with no referrers.
Map<String, List<String>> findMissingReferences(SurfaceDefinition definition) {
  final Map<String, Component> components = definition.components;
  final missing = <String, List<String>>{};
  if (components.isNotEmpty && !components.containsKey('root')) {
    missing['root'] = [];
  }
  for (final MapEntry(key: String id, value: Component component)
      in components.entries) {
    for (final String ref in referencedIds(component.properties)) {
      if (!components.containsKey(ref)) {
        (missing[ref] ??= []).add(id);
      }
    }
  }
  return missing;
}

/// The child component IDs referenced by a component's properties.
Iterable<String> referencedIds(Map<String, Object?> properties) sync* {
  for (final String key in const ['child', 'trigger', 'content']) {
    if (properties[key] case final String id) yield id;
  }
  switch (properties['children']) {
    case final List<Object?> ids:
      yield* ids.whereType<String>();
    case {'componentId': final String id}:
      yield id;
  }
  if (properties['tabs'] case final List<Object?> tabs) {
    for (final Object? tab in tabs) {
      if (tab case {'content': final String id} || {'child': final String id}) {
        yield id;
      }
    }
  }
}
