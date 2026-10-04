import 'package:analyzer/source/line_info.dart';

import 'shorthand_visitor.dart';

/// Comment marker that keeps every finding on the line it ends.
const ignoreMarker = 'dot_shorthand: ignore';

/// Name of the analyzer rule, as used in `// ignore:` comments.
const ruleName = 'prefer_dot_shorthand';

final _ignoreForFile = RegExp(
  r'//[ \t]*ignore_for_file[ \t]*:(.*)$',
  multiLine: true,
  caseSensitive: false,
);

final _ignoreLine = RegExp(
  r'//[ \t]*ignore[ \t]*:(.*)$',
  multiLine: true,
  caseSensitive: false,
);

const _pluginName = 'dot_shorthand';

bool _covers(String list) {
  final names = [for (final name in list.split(',')) name.trim().toLowerCase()];
  return names.contains(ruleName) ||
      names.contains('$_pluginName/$ruleName') ||
      names.contains('type=lint');
}

/// The ignore comments of one file.
///
/// Honours [ignoreMarker] on the same line, `// ignore: prefer_dot_shorthand`
/// or `// ignore: dot_shorthand/prefer_dot_shorthand` on the same or previous
/// line, and `// ignore_for_file:` for either name or `type=lint`.
///
/// The file is scanned for `ignore_for_file` once, so [covers] only reads the
/// finding's own lines.
class IgnoreComments {
  IgnoreComments(this.content, this.lineInfo)
    : wholeFile = _ignoreForFile
          .allMatches(content)
          .any((match) => _covers(match.group(1)!));

  final String content;
  final LineInfo lineInfo;

  /// Whether an `ignore_for_file` comment covers every finding.
  final bool wholeFile;

  /// Whether an ignore comment covers [finding].
  bool covers(Finding finding) {
    if (wholeFile) return true;
    for (final line in [finding.line - 1, finding.line]) {
      final text = _lineText(line);
      if (text == null) continue;
      if (text.contains(ignoreMarker) && line == finding.line) return true;
      final match = _ignoreLine.firstMatch(text);
      if (match != null && _covers(match.group(1)!)) return true;
    }
    return false;
  }

  String? _lineText(int line) {
    if (line < 1 || line > lineInfo.lineCount) return null;
    final start = lineInfo.getOffsetOfLine(line - 1);
    final end = line < lineInfo.lineCount
        ? lineInfo.getOffsetOfLine(line)
        : content.length;
    return content.substring(start, end);
  }
}

/// Whether an ignore comment in [content] covers [finding].
///
/// Scans the whole file on each call; for several findings in one file build
/// one [IgnoreComments] and call [IgnoreComments.covers].
bool isIgnored(String content, LineInfo lineInfo, Finding finding) =>
    IgnoreComments(content, lineInfo).covers(finding);
