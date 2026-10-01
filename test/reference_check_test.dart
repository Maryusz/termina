import 'package:flutter_test/flutter_test.dart';
import 'package:genui/genui.dart';
import 'package:termina/src/genui/reference_check.dart';

SurfaceDefinition _surface(List<Map<String, Object?>> components) =>
    SurfaceDefinition.fromJson({
      'surfaceId': 's',
      'components': {for (final c in components) c['id'] as String: c},
    });

void main() {
  test('reports children that were never defined', () {
    final missing = findMissingReferences(
      _surface([
        {
          'id': 'root',
          'component': 'Column',
          'children': ['intro', 'limitSlider'],
        },
        {'id': 'intro', 'component': 'Text', 'text': 'ciao'},
      ]),
    );
    expect(missing, {
      'limitSlider': ['root'],
    });
  });

  test('follows child, tabs and templates', () {
    final missing = findMissingReferences(
      _surface([
        {'id': 'root', 'component': 'Card', 'child': 'tabs'},
        {
          'id': 'tabs',
          'component': 'Tabs',
          'tabs': [
            {'label': 'A', 'content': 'a'},
            {'label': 'B', 'content': 'b'},
          ],
        },
        {
          'id': 'a',
          'component': 'List',
          'children': {'componentId': 'row', 'path': '/items'},
        },
      ]),
    );
    expect(missing.keys, unorderedEquals(['b', 'row']));
  });

  test('reports a missing root', () {
    expect(
      findMissingReferences(
        _surface([
          {'id': 'x', 'component': 'Text', 'text': 'ciao'},
        ]),
      ),
      {'root': <String>[]},
    );
  });

  test('a complete surface has no problems', () {
    expect(
      findMissingReferences(
        _surface([
          {'id': 'root', 'component': 'Text', 'text': 'ciao'},
        ]),
      ),
      isEmpty,
    );
  });
}
