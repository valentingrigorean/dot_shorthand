/// Finds and rewrites member references that a context type already
/// supplies, so `Color.red` becomes `.red`.
///
/// [DotShorthandScan] resolves files under a set of paths and reports every
/// place as a [Finding]. [applyFindings] rewrites them on disk.
library;

import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/session.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/source/line_info.dart';
import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;

import 'src/shorthand_visitor.dart';

export 'src/shorthand_visitor.dart'
    show Finding, ShorthandVisitor, isGeneratedSource;

/// Comment marker that keeps every finding on the line it ends.
const ignoreMarker = 'dot_shorthand: ignore';

/// File name suffixes that are never scanned.
const generatedSuffixes = <String>[
  '.g.dart',
  '.gen.dart',
  '.freezed.dart',
  '.mocks.dart',
];

/// Scans the Dart files under a set of paths for dot shorthand candidates.
///
/// Each path is resolved inside the nearest enclosing package so that
/// context types are known.
class DotShorthandScan {
  DotShorthandScan({
    required Iterable<String> paths,
    Iterable<String> exclude = const [],
  }) : targets = [for (final path in paths) p.normalize(p.absolute(path))],
       excludes = [for (final pattern in exclude) Glob(pattern)];

  final List<String> targets;

  /// Globs matched against paths relative to the package root.
  final List<Glob> excludes;

  /// Imports the analyzer reported as unused or unnecessary during the last
  /// [scan], keyed by file path.
  final unusedImports = <String, List<UnusedImport>>{};

  /// Resolves every candidate file and returns the findings that are not
  /// covered by an ignore comment.
  ///
  /// When [only] is given, just those files are scanned.
  Future<List<Finding>> scan([Iterable<String>? only]) async {
    final selected = only == null
        ? null
        : {for (final path in only) p.normalize(p.absolute(path))};
    final collection = AnalysisContextCollection(includedPaths: contextRoots());
    final findings = <Finding>[];
    unusedImports.clear();
    for (final context in collection.contexts) {
      final root = context.contextRoot.root.path;
      final files =
          context.contextRoot
              .analyzedFiles()
              .where((file) => _isCandidate(file, root))
              .where((file) => selected == null || selected.contains(file))
              .toList()
            ..sort();
      for (final file in files) {
        final unit = await context.currentSession.getResolvedUnit(file);
        if (unit is! ResolvedUnitResult) continue;
        if (isGeneratedSource(unit.content)) continue;
        unusedImports[file] = _unusedImports(unit);
        await _recordLibraryImports(context.currentSession, unit, selected);
        final visitor = ShorthandVisitor(unit);
        unit.unit.accept(visitor);
        findings.addAll(
          visitor.findings.where(
            (f) => !isIgnored(unit.content, unit.lineInfo, f),
          ),
        );
      }
    }
    return findings;
  }

  List<String> contextRoots() {
    final roots = <String>{};
    for (final target in targets) {
      roots.add(packageRootOf(target) ?? target);
    }
    return roots.toList()..sort();
  }

  /// The nearest directory above [path] that holds a `pubspec.yaml`.
  static String? packageRootOf(String path) {
    var directory = FileSystemEntity.isDirectorySync(path)
        ? Directory(path)
        : Directory(p.dirname(path));
    while (true) {
      if (File(p.join(directory.path, 'pubspec.yaml')).existsSync()) {
        return directory.path;
      }
      final parent = directory.parent;
      if (parent.path == directory.path) return null;
      directory = parent;
    }
  }

  /// A rewrite in a part file can leave an import in its library unused, and
  /// the library is not among the rescanned files. Record its imports too.
  Future<void> _recordLibraryImports(
    AnalysisSession session,
    ResolvedUnitResult unit,
    Set<String>? selected,
  ) async {
    if (selected == null) return;
    final library = unit.libraryElement.firstFragment.source.fullName;
    if (library == unit.path || selected.contains(library)) return;
    if (unusedImports.containsKey(library)) return;
    final result = await session.getResolvedUnit(library);
    if (result is! ResolvedUnitResult) return;
    unusedImports[library] = _unusedImports(result);
  }

  static const _removableImportCodes = {'unused_import', 'unnecessary_import'};

  static const _unusedShownNameCode = 'unused_shown_name';

  /// Whole directives the analyzer reports as unused or unnecessary, then the
  /// shown names it reports as unused in the directives that stay.
  static List<UnusedImport> _unusedImports(ResolvedUnitResult unit) {
    final imports = <UnusedImport>[];
    final unusedNames = <ImportDirective, Set<int>>{};
    for (final diagnostic in unit.diagnostics) {
      final code = diagnostic.diagnosticCode.lowerCaseName;
      final removable = _removableImportCodes.contains(code);
      if (!removable && code != _unusedShownNameCode) continue;
      final directive = _directiveAt(unit.unit, diagnostic.offset);
      if (directive == null || directive.uri.stringValue == null) continue;
      if (removable) {
        imports.add(_wholeDirective(unit, directive));
      } else {
        unusedNames.putIfAbsent(directive, () => {}).add(diagnostic.offset);
      }
    }
    for (final entry in unusedNames.entries) {
      imports.addAll(_shownNames(unit, entry.key, entry.value));
    }
    return imports;
  }

  static ImportDirective? _directiveAt(CompilationUnit unit, int offset) {
    for (final directive in unit.directives) {
      if (directive is! ImportDirective) continue;
      if (offset >= directive.offset && offset < directive.end) {
        return directive;
      }
    }
    return null;
  }

  static UnusedImport _wholeDirective(
    ResolvedUnitResult unit,
    ImportDirective directive,
  ) {
    final content = unit.content;
    var end = directive.end;
    while (end < content.length &&
        (content[end] == ' ' || content[end] == '\t')) {
      end++;
    }
    if (content.startsWith('\r\n', end)) {
      end += 2;
    } else if (content.startsWith('\n', end)) {
      end += 1;
    }
    return UnusedImport(
      path: unit.path,
      uri: directive.uri.stringValue!,
      deleteStart: directive.offset,
      deleteEnd: end,
    );
  }

  /// One removal per unused name in the `show` lists of [directive].
  ///
  /// A name followed by a kept name goes together with its own comma; a name
  /// with no kept name after it goes together with the comma before it. Either
  /// way every range can be applied on its own, so a subset of them is safe.
  static Iterable<UnusedImport> _shownNames(
    ResolvedUnitResult unit,
    ImportDirective directive,
    Set<int> offsets,
  ) sync* {
    for (final combinator in directive.combinators) {
      if (combinator is! ShowCombinator) continue;
      final names = combinator.shownNames;
      final unused = [
        for (var i = 0; i < names.length; i++)
          if (offsets.contains(names[i].offset)) i,
      ];
      if (unused.length == names.length) continue;
      for (final i in unused) {
        final keptAfter = names.indexWhere(
          (n) => !offsets.contains(n.offset),
          i,
        );
        yield UnusedImport(
          path: unit.path,
          uri: directive.uri.stringValue!,
          name: names[i].name,
          deleteStart: keptAfter == -1 ? names[i - 1].end : names[i].offset,
          deleteEnd: keptAfter == -1 ? names[i].end : names[i + 1].offset,
        );
      }
    }
  }

  bool _isCandidate(String file, String root) {
    if (!file.endsWith('.dart')) return false;
    if (generatedSuffixes.any(file.endsWith)) return false;
    if (!targets.any((t) => t == file || p.isWithin(t, file))) return false;
    final relative = p.isWithin(root, file)
        ? p.relative(file, from: root)
        : file;
    return !excludes.any((g) => g.matches(relative) || g.matches(file));
  }
}

/// An import directive the analyzer reports as unused or unnecessary, or
/// one name in its `show` list when [name] is set.
class UnusedImport {
  UnusedImport({
    required this.path,
    required this.uri,
    this.name,
    required this.deleteStart,
    required this.deleteEnd,
  });

  final String path;
  final String uri;

  /// The shown name to drop; null when the whole directive goes.
  final String? name;

  /// Start of the directive, or of the name and its separator.
  final int deleteStart;

  /// End of the directive's line, including the line break, or of the name
  /// and its separator.
  final int deleteEnd;

  /// What [newlyUnusedImports] compares between two scans.
  String get key => name == null ? uri : '$uri show $name';
}

/// The imports in [after] that were not already unused in [before]: the ones a
/// rewrite made redundant. Files missing from [before] are left alone.
List<UnusedImport> newlyUnusedImports(
  Map<String, List<UnusedImport>> before,
  Map<String, List<UnusedImport>> after,
) {
  final result = <UnusedImport>[];
  for (final entry in after.entries) {
    final earlier = before[entry.key];
    if (earlier == null) continue;
    final known = {for (final i in earlier) i.key};
    result.addAll(entry.value.where((i) => !known.contains(i.key)));
  }
  return result;
}

/// Deletes [imports], whole directives and shown names alike, from disk and
/// returns the paths of the changed files, sorted.
List<String> removeImports(List<UnusedImport> imports) {
  final byFile = <String, List<UnusedImport>>{};
  for (final import in imports) {
    byFile.putIfAbsent(import.path, () => []).add(import);
  }
  for (final entry in byFile.entries) {
    final file = File(entry.key);
    var content = file.readAsStringSync();
    final ordered = entry.value.toList()
      ..sort((a, b) => b.deleteStart.compareTo(a.deleteStart));
    for (final import in ordered) {
      content = content.replaceRange(import.deleteStart, import.deleteEnd, '');
    }
    file.writeAsStringSync(content);
  }
  return byFile.keys.toList()..sort();
}

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

/// Whether an ignore comment in [content] covers [finding].
///
/// Honours [ignoreMarker] on the same line, `// ignore: prefer_dot_shorthand`
/// or `// ignore: dot_shorthand/prefer_dot_shorthand` on the same or previous
/// line, and `// ignore_for_file:` for either name or `type=lint`.
bool isIgnored(String content, LineInfo lineInfo, Finding finding) {
  for (final match in _ignoreForFile.allMatches(content)) {
    if (_covers(match.group(1)!)) return true;
  }
  for (final line in [finding.line - 1, finding.line]) {
    final text = _lineText(content, lineInfo, line);
    if (text == null) continue;
    if (text.contains(ignoreMarker) && line == finding.line) return true;
    final match = _ignoreLine.firstMatch(text);
    if (match != null && _covers(match.group(1)!)) return true;
  }
  return false;
}

String? _lineText(String content, LineInfo lineInfo, int line) {
  if (line < 1 || line > lineInfo.lineCount) return null;
  final start = lineInfo.getOffsetOfLine(line - 1);
  final end = line < lineInfo.lineCount
      ? lineInfo.getOffsetOfLine(line)
      : content.length;
  return content.substring(start, end);
}

/// Deletes the type name of every finding on disk and returns the paths of
/// the files that changed, sorted.
List<String> applyFindings(List<Finding> findings) {
  final byFile = <String, List<Finding>>{};
  for (final finding in findings) {
    byFile.putIfAbsent(finding.path, () => []).add(finding);
  }
  for (final entry in byFile.entries) {
    final file = File(entry.key);
    var content = file.readAsStringSync();
    final ordered = entry.value.toList()
      ..sort((a, b) => b.deleteStart.compareTo(a.deleteStart));
    for (final finding in ordered) {
      content = content.replaceRange(
        finding.deleteStart,
        finding.deleteEnd,
        '',
      );
    }
    file.writeAsStringSync(content);
  }
  return byFile.keys.toList()..sort();
}
