import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:dot_shorthand/dot_shorthand.dart';
import 'package:path/path.dart' as p;

const marker = '// fixture body';

const preamble =
    '''
enum Color { red, green }

class Insets extends Geom {
  const Insets.all(this.value);
  factory Insets.doubled(int value) => Insets.all(value * 2);
  final int value;
  static const Insets zero = .all(0);
  static const Insets infinity = .all(999);
  static Insets latest = .all(7);
  static Insets get one => const .all(1);
  static Insets make(int value) => .all(value);
  static Insets of(Insets other) => other;
}

abstract class Geom {
  const Geom();
  const factory Geom.all(int value) = Insets.all;
  static const Geom infinity = .all(-1);
  static const Geom zero = Insets.zero;
}

abstract class Frame {
  const Frame();
  static const Frame? edge = Panel.edge;
  static const Object all = Panel.all;
}

class Panel extends Frame {
  const Panel();
  static const Panel edge = Panel();
  static const Panel all = Panel();
}

class Plain {
  const Plain(this.value);
  final int value;
}

class Box<T> {
  const Box.of(this.value);
  final T value;
}

class Slot<T> {
  Slot(this.value);
  T value;
}

T id<T>(T value) => value;

void expect(dynamic actual, dynamic matcher) {}

$marker
''';

class Fixture {
  Fixture(this.root, this.files);

  final Directory root;
  final Map<String, String> files;

  String get lib => p.join(root.path, 'lib');

  String path(String name) => p.join(lib, name);

  String read(String name) => File(path(name)).readAsStringSync();

  void dispose() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  }
}

Fixture writeFixture(Map<String, String> files) {
  final root = Directory.systemTemp.createTempSync('dot_shorthand_');
  File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('''
name: fixture
publish_to: none

environment:
  sdk: ^3.13.2
''');
  Directory(p.join(root.path, 'lib')).createSync();
  files.forEach((name, source) {
    final file = File(p.join(root.path, 'lib', name));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(source);
  });
  return Fixture(root, files);
}

/// Wraps [body] in the shared declarations and returns the whole source.
String fixtureSource(String body) => '$preamble$body';

Future<List<Finding>> scanSource(
  String body, {
  List<String> exclude = const [],
}) async {
  final fixture = writeFixture({'fixture.dart': fixtureSource(body)});
  try {
    return await DotShorthandScan(
      paths: [fixture.lib],
      exclude: exclude,
    ).scan();
  } finally {
    fixture.dispose();
  }
}

Future<String> fixSource(String body) async {
  final fixture = writeFixture({'fixture.dart': fixtureSource(body)});
  try {
    final scan = DotShorthandScan(paths: [fixture.lib]);
    applyFindings(await scan.scan());
    final rest = await scan.scan();
    if (rest.isNotEmpty) {
      throw StateError(
        'findings left after the fix: ${shorthands(rest).join(', ')}',
      );
    }
    final errors = await compileErrors(fixture);
    if (errors.isNotEmpty) {
      throw StateError(
        'the fixed source does not compile:\n${errors.join('\n')}',
      );
    }
    final text = fixture.read('fixture.dart');
    return text.substring(text.indexOf(marker) + marker.length + 1);
  } finally {
    fixture.dispose();
  }
}

/// Every error the analyzer reports for the Dart sources of [fixture].
///
/// A fixture body that does not compile would make a negative case pass for the
/// wrong reason, and a rewrite that does not compile is the failure that
/// matters most, so both ends are checked against the analyzer itself.
Future<List<String>> compileErrors(Fixture fixture) async {
  final collection = AnalysisContextCollection(includedPaths: [fixture.lib]);
  final errors = <String>[];
  for (final context in collection.contexts) {
    final files = context.contextRoot.analyzedFiles().where(
      (file) => file.endsWith('.dart'),
    );
    for (final file in files) {
      final unit = await context.currentSession.getResolvedUnit(file);
      if (unit is! ResolvedUnitResult) continue;
      for (final diagnostic in unit.diagnostics) {
        if (diagnostic.severity != .error) continue;
        final at = unit.lineInfo.getLocation(diagnostic.offset);
        errors.add(
          '${p.basename(file)}:${at.lineNumber}:${at.columnNumber} '
          '${diagnostic.message}',
        );
      }
    }
  }
  return errors;
}

List<String> shorthands(List<Finding> findings) => [
  for (final finding in findings) '${finding.source} -> ${finding.shorthand}',
];
