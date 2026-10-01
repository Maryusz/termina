import 'package:flutter_test/flutter_test.dart';
import 'package:termina/src/command/command_template.dart';

void main() {
  String render(
    String template,
    Map<String, Object?> data, {
    QuoteStyle style = QuoteStyle.posix,
  }) => CommandTemplate(template).render((p) => data[p], style: style);

  test('substitutes plain values', () {
    expect(render('ls {{/dir}}', {'/dir': '/tmp'}), 'ls /tmp');
  });

  test('drops empty values and collapses spaces', () {
    expect(render('ls {{/a}}  {{/b}} {{/dir}}', {'/dir': 'x'}), 'ls x');
  });

  test('conditional flags', () {
    const t = 'ls {{/all?-a}} {{/long?-l}} {{!/long?-1}}';
    expect(render(t, {'/all': true, '/long': false}), 'ls -a -1');
    expect(render(t, {'/all': false, '/long': true}), 'ls -l');
  });

  test('conditional text with value', () {
    expect(render('head {{/n?-n %s}} f', {'/n': 5}), 'head -n 5 f');
    expect(render('head {{/n?-n %s}} f', {'/n': 0}), 'head f');
    expect(render('x {{/d?-d %s}}', {'/d': 2.0}), 'x -d 2');
  });

  test('quotes unsafe strings', () {
    expect(render('echo {{/m}}', {'/m': "it's ok"}), r"echo 'it'\''s ok'");
    expect(
      render('echo {{/m}}', {'/m': "it's ok"}, style: QuoteStyle.powershell),
      "echo 'it''s ok'",
    );
    expect(render('cat {{/f}}', {'/f': '~/a b.txt'}), "cat '~/a b.txt'");
  });

  test('lists expand to multiple words', () {
    expect(
      render('rm {{/files}}', {
        '/files': ['a.txt', 'b c.txt'],
      }),
      "rm a.txt 'b c.txt'",
    );
  });

  test('keeps whitespace inside literal quotes', () {
    expect(render('grep "a  b" {{/x}}  f', {}), 'grep "a  b" f');
  });

  test('collects referenced paths', () {
    expect(CommandTemplate('a {{/x}} {{!/y?-z}} {{ /x?q }}').paths, {
      '/x',
      '/y',
    });
  });
}
