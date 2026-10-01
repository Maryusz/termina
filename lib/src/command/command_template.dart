/// How values are quoted when they are inserted into a command line.
enum QuoteStyle {
  /// POSIX shells (bash, zsh, sh): single quotes, `'` becomes `'\''`.
  posix,

  /// PowerShell: single quotes, `'` becomes `''`.
  powershell,
}

/// A command line with placeholders bound to the GenUI data model.
///
/// Syntax:
/// - `{{/path}}`: the value at `/path`, quoted when needed. Empty strings,
///   `null` and `false` render nothing; lists render each element.
/// - `{{/path?text}}`: `text` when the value at `/path` is truthy. Inside
///   `text`, `%s` is replaced by the quoted value.
/// - `{{!/path?text}}`: `text` when the value at `/path` is falsy.
///
/// Example: `ls {{/all?-a}} {{/long?-l}} {{/dir}}`.
class CommandTemplate {
  CommandTemplate(this.source);

  final String source;

  static final RegExp _placeholder = RegExp(
    r'\{\{\s*(!?)\s*(/[^}?]*?)\s*(?:\?([^}]*))?\}\}',
  );

  /// The data model paths referenced by this template.
  Set<String> get paths => {
    for (final RegExpMatch m in _placeholder.allMatches(source)) m.group(2)!,
  };

  /// Renders the command, reading values with [lookup].
  String render(
    Object? Function(String path) lookup, {
    QuoteStyle style = QuoteStyle.posix,
  }) {
    final String raw = source.replaceAllMapped(_placeholder, (m) {
      final bool negated = m.group(1) == '!';
      final Object? value = lookup(m.group(2)!);
      final String? text = m.group(3);
      if (text == null) {
        return negated ? '' : formatValue(value, style);
      }
      if (isTruthy(value) == negated) return '';
      return text.replaceAll('%s', formatValue(value, style));
    });
    return collapseWhitespace(raw);
  }

  /// Whether [value] counts as "set" for conditional placeholders.
  static bool isTruthy(Object? value) => switch (value) {
    null => false,
    bool b => b,
    num n => n != 0,
    String s => s.trim().isNotEmpty,
    Iterable<Object?> l => l.isNotEmpty,
    Map<Object?, Object?> m => m.isNotEmpty,
    _ => true,
  };

  /// Formats [value] as one or more shell words.
  static String formatValue(Object? value, QuoteStyle style) => switch (value) {
    null || bool() => '',
    int n => '$n',
    double d => d == d.truncateToDouble() ? '${d.toInt()}' : '$d',
    String s => s.trim().isEmpty ? '' : quote(s.trim(), style),
    Iterable<Object?> l =>
      l.map((e) => formatValue(e, style)).where((e) => e.isNotEmpty).join(' '),
    _ => quote('$value', style),
  };

  static final RegExp _safeWord = RegExp(r'^[A-Za-z0-9_@%+=:,./~-]+$');

  /// Quotes [word] for [style] unless it only contains safe characters.
  static String quote(String word, QuoteStyle style) {
    if (_safeWord.hasMatch(word)) return word;
    return switch (style) {
      QuoteStyle.posix => "'${word.replaceAll("'", r"'\''")}'",
      QuoteStyle.powershell => "'${word.replaceAll("'", "''")}'",
    };
  }

  /// Collapses runs of whitespace outside of quotes and trims the result.
  static String collapseWhitespace(String command) {
    final buffer = StringBuffer();
    String? openQuote;
    var pendingSpace = false;
    for (final int rune in command.runes) {
      final char = String.fromCharCode(rune);
      if (openQuote == null && (char == ' ' || char == '\t')) {
        pendingSpace = buffer.isNotEmpty;
        continue;
      }
      if (pendingSpace) {
        buffer.write(' ');
        pendingSpace = false;
      }
      if (openQuote == null && (char == "'" || char == '"')) {
        openQuote = char;
      } else if (char == openQuote) {
        openQuote = null;
      }
      buffer.write(char);
    }
    return buffer.toString();
  }
}
