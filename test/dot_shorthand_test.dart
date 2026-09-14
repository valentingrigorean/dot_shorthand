import 'dart:convert';
import 'dart:io';

import 'package:dot_shorthand/dot_shorthand.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support.dart';

void main() {
  group('context kinds', () {
    test('default parameter values', () async {
      const body = '''
class Holder {
  const Holder({this.color = Color.red, this.insets = Insets.zero});
  final Color color;
  final Insets insets;
}
''';
      expect(shorthands(await scanSource(body)), [
        'Color.red -> .red',
        'Insets.zero -> .zero',
      ]);
      expect(await fixSource(body), '''
class Holder {
  const Holder({this.color = .red, this.insets = .zero});
  final Color color;
  final Insets insets;
}
''');
    });

    test('named and positional arguments', () async {
      const body = '''
void take(Color first, {Color? second}) {}
void run() => take(Color.red, second: Color.green);
''';
      expect(shorthands(await scanSource(body)), [
        'Color.red -> .red',
        'Color.green -> .green',
      ]);
      expect(await fixSource(body), '''
void take(Color first, {Color? second}) {}
void run() => take(.red, second: .green);
''');
    });

    test('typed declarations and assignments', () async {
      const body = '''
final Color topLevel = Color.red;

Color assign() {
  Color value = Color.green;
  value = Color.red;
  return value;
}
''';
      expect(shorthands(await scanSource(body)), [
        'Color.red -> .red',
        'Color.green -> .green',
        'Color.red -> .red',
      ]);
      expect(await fixSource(body), '''
final Color topLevel = .red;

Color assign() {
  Color value = .green;
  value = .red;
  return value;
}
''');
    });

    test('constructor field initializers', () async {
      const body = '''
class Holder {
  Holder() : color = Color.green, insets = Insets.zero;
  final Color color;
  final Insets insets;
}
''';
      expect(shorthands(await scanSource(body)), [
        'Color.green -> .green',
        'Insets.zero -> .zero',
      ]);
      expect(await fixSource(body), '''
class Holder {
  Holder() : color = .green, insets = .zero;
  final Color color;
  final Insets insets;
}
''');
    });

    test('returns with a declared return type', () async {
      const body = '''
Color sync() => Color.red;

Future<Color> asynchronous() async {
  return Color.green;
}

Insets fromStaticMethod() {
  return Insets.make(2);
}
''';
      expect(shorthands(await scanSource(body)), [
        'Color.red -> .red',
        'Color.green -> .green',
        'Insets.make(2) -> .make(2)',
      ]);
      expect(await fixSource(body), '''
Color sync() => .red;

Future<Color> asynchronous() async {
  return .green;
}

Insets fromStaticMethod() {
  return .make(2);
}
''');
    });

    test('equality against a typed left side', () async {
      const body = '''
bool isRed(Color value) => value == Color.red;
bool notGreen(Color value) => value != Color.green;
''';
      expect(shorthands(await scanSource(body)), [
        'Color.red -> .red',
        'Color.green -> .green',
      ]);
      expect(await fixSource(body), '''
bool isRed(Color value) => value == .red;
bool notGreen(Color value) => value != .green;
''');
    });

    test('switch cases', () async {
      const body = '''
String label(Color value) {
  switch (value) {
    case Color.red:
      return 'red';
    case Color.green:
      return 'green';
  }
}
''';
      expect(shorthands(await scanSource(body)), [
        'Color.red -> .red',
        'Color.green -> .green',
      ]);
      expect(await fixSource(body), '''
String label(Color value) {
  switch (value) {
    case .red:
      return 'red';
    case .green:
      return 'green';
  }
}
''');
    });

    test('if-case patterns', () async {
      const body = '''
bool isRed(Color value) {
  if (value case Color.red) return true;
  return false;
}
''';
      expect(shorthands(await scanSource(body)), ['Color.red -> .red']);
      expect(await fixSource(body), '''
bool isRed(Color value) {
  if (value case .red) return true;
  return false;
}
''');
    });

    test('conditional branches', () async {
      const body = '''
Color pick(bool flag) => flag ? Color.red : Color.green;
''';
      expect(shorthands(await scanSource(body)), [
        'Color.red -> .red',
        'Color.green -> .green',
      ]);
      expect(await fixSource(body), '''
Color pick(bool flag) => flag ? .red : .green;
''');
    });

    test('collection elements with a known element type', () async {
      const body = '''
List<Color> explicit() => <Color>[Color.red];
List<Color> fromContext() => [Color.green];
Set<Color> asSet() => <Color>{Color.red};
''';
      expect(shorthands(await scanSource(body)), [
        'Color.red -> .red',
        'Color.green -> .green',
        'Color.red -> .red',
      ]);
      expect(await fixSource(body), '''
List<Color> explicit() => <Color>[.red];
List<Color> fromContext() => [.green];
Set<Color> asSet() => <Color>{.red};
''');
    });
  });

  group('generics', () {
    test('a type argument fixed by the receiver is a context', () async {
      const body = '''
void fill(List<Color> target) => target.add(Color.red);
''';
      expect(shorthands(await scanSource(body)), ['Color.red -> .red']);
      expect(await fixSource(body), '''
void fill(List<Color> target) => target.add(.red);
''');
    });

    test('a field of a generic class', () async {
      const body = '''
void store(Slot<Color> slot) {
  slot.value = Color.red;
}

Color read(Slot<Color> slot) => slot.value;
''';
      expect(shorthands(await scanSource(body)), ['Color.red -> .red']);
      expect(await fixSource(body), '''
void store(Slot<Color> slot) {
  slot.value = .red;
}

Color read(Slot<Color> slot) => slot.value;
''');
    });

    test('an awaited generic return type', () async {
      const body = '''
Future<Insets> load() async => Insets.zero;
''';
      expect(shorthands(await scanSource(body)), ['Insets.zero -> .zero']);
      expect(await fixSource(body), '''
Future<Insets> load() async => .zero;
''');
    });
  });

  group('member kinds', () {
    test(
      'enum values, static fields, constants, getters and methods',
      () async {
        const body = '''
final Color value = Color.red;
final Insets constant = Insets.zero;
final Insets field = Insets.latest;
final Insets getter = Insets.one;
final Insets method = Insets.make(3);
''';
        expect(shorthands(await scanSource(body)), [
          'Color.red -> .red',
          'Insets.zero -> .zero',
          'Insets.latest -> .latest',
          'Insets.one -> .one',
          'Insets.make(3) -> .make(3)',
        ]);
        expect(await fixSource(body), '''
final Color value = .red;
final Insets constant = .zero;
final Insets field = .latest;
final Insets getter = .one;
final Insets method = .make(3);
''');
      },
    );

    test('named constructors', () async {
      const body = '''
final Insets named = Insets.all(4);
final Insets constant = const Insets.all(5);
''';
      expect(shorthands(await scanSource(body)), [
        'Insets.all(4) -> .all(4)',
        'const Insets.all(5) -> .all(5)',
      ]);
      expect(await fixSource(body), '''
final Insets named = .all(4);
final Insets constant = const .all(5);
''');
    });

    test('factories', () async {
      const body = '''
final Insets doubled = Insets.doubled(6);
Insets make() => Insets.doubled(7);
''';
      expect(shorthands(await scanSource(body)), [
        'Insets.doubled(6) -> .doubled(6)',
        'Insets.doubled(7) -> .doubled(7)',
      ]);
      expect(await fixSource(body), '''
final Insets doubled = .doubled(6);
Insets make() => .doubled(7);
''');
    });
  });

  group('supertype context', () {
    test('a supertype constructor that redirects to the written one', () async {
      const body = '''
void take(Geom value) {}
void run() => take(Insets.all(8));
''';
      expect(shorthands(await scanSource(body)), ['Insets.all(8) -> .all(8)']);
      expect(await fixSource(body), '''
void take(Geom value) {}
void run() => take(.all(8));
''');
    });

    test('a supertype static const aliasing the same object', () async {
      const body = '''
final Geom aliased = Insets.zero;
final Geom direct = Geom.zero;
''';
      expect(shorthands(await scanSource(body)), [
        'Insets.zero -> .zero',
        'Geom.zero -> .zero',
      ]);
      expect(await fixSource(body), '''
final Geom aliased = .zero;
final Geom direct = .zero;
''');
    });

    test(
      'an alias initializer and a wider alias type keep the type name',
      () async {
        const body = '''
final Frame? nullable = Panel.edge;
final Frame nonNull = Panel.edge;
final Frame wide = Panel.all;
final Object object = Panel.all;
''';
        expect(shorthands(await scanSource(body)), ['Panel.edge -> .edge']);
        expect(await fixSource(body), '''
final Frame? nullable = .edge;
final Frame nonNull = Panel.edge;
final Frame wide = Panel.all;
final Object object = Panel.all;
''');
      },
    );

    test(
      'a supertype static naming a different object keeps the type name',
      () async {
        const body = '''
final Geom fromSubtype = Insets.infinity;
final Geom fromSupertype = Geom.infinity;
''';
        expect(shorthands(await scanSource(body)), [
          'Geom.infinity -> .infinity',
        ]);
        expect(await fixSource(body), '''
final Geom fromSubtype = Insets.infinity;
final Geom fromSupertype = .infinity;
''');
      },
    );

    test(
      'a supertype without the written member keeps the type name',
      () async {
        const body = '''
void take(Geom value) {}
void run() => take(Insets.one);
''';
        expect(await scanSource(body), isEmpty);
        expect(await fixSource(body), body);
      },
    );
  });

  group('pitfalls stay as written', () {
    test('the unnamed constructor', () async {
      const body = '''
final Plain plain = Plain(6);
Plain build() => const Plain(7);
''';
      expect(await scanSource(body), isEmpty);
      expect(await fixSource(body), body);
    });

    test('the values getter', () async {
      const body = '''
List<Color> all() => Color.values;
Iterable<Color> every() => Color.values;
''';
      expect(await scanSource(body), isEmpty);
      expect(await fixSource(body), body);
    });

    test('a property access chain', () async {
      const body = '''
String named() => Color.red.name;
int size() => Insets.zero.value;
''';
      expect(await scanSource(body), isEmpty);
      expect(await fixSource(body), body);
    });

    test('a collection-for element without a context type', () async {
      const body = '''
final loop = [for (final value in Color.values) Color.red];
''';
      expect(await scanSource(body), isEmpty);
      expect(await fixSource(body), body);
    });

    test('a list literal passed to an untyped parameter', () async {
      const body = '''
void run() {
  expect([Color.red], Color.green);
}
''';
      expect(await scanSource(body), isEmpty);
      expect(await fixSource(body), body);
    });

    test('a fold seed', () async {
      const body = '''
Color seed(List<Color> values) =>
    values.fold(Color.red, (previous, value) => value);
''';
      expect(await scanSource(body), isEmpty);
      expect(await fixSource(body), body);
    });

    test('a type inferred from the expression itself', () async {
      const body = '''
var c = Color.red;
final x = Insets.zero;
''';
      expect(await scanSource(body), isEmpty);
      expect(await fixSource(body), body);
    });

    test('a written type carrying type arguments', () async {
      const body = '''
final Box<int> explicit = Box<int>.of(1);
''';
      expect(await scanSource(body), isEmpty);
      expect(await fixSource(body), body);
    });

    test('an argument typed by the invocation own type parameters', () async {
      const body = '''
final Color same = id(Color.red);
''';
      expect(await scanSource(body), isEmpty);
      expect(await fixSource(body), body);
    });
  });

  group('rewriting', () {
    test('a finding inside another finding', () async {
      const body = '''
final Insets nested = Insets.of(Insets.zero);
''';
      expect(shorthands(await scanSource(body)), [
        'Insets.zero -> .zero',
        'Insets.of(Insets.zero) -> .of(Insets.zero)',
      ]);
      expect(await fixSource(body), '''
final Insets nested = .of(.zero);
''');
    });
  });

  group('knobs', () {
    test('an ignore comment keeps its line', () async {
      const body = '''
final Color kept = Color.red; // dot_shorthand: ignore
final Color rewritten = Color.green;
''';
      expect(shorthands(await scanSource(body)), ['Color.green -> .green']);
      expect(await fixSource(body), '''
final Color kept = Color.red; // dot_shorthand: ignore
final Color rewritten = .green;
''');
    });

    test('a file with the FlutterFire header is never rewritten', () async {
      const source = '''
// File generated by FlutterFire CLI.
enum Color { red, green }

final Color value = Color.red;
''';
      final fixture = writeFixture({'firebase_options.dart': source});
      addTearDown(fixture.dispose);
      final scan = DotShorthandScan(paths: [fixture.lib]);
      expect(await scan.scan(), isEmpty);
      applyFindings(await scan.scan());
      expect(fixture.read('firebase_options.dart'), source);
    });

    test('a file level lint ignore keeps every finding', () async {
      const body = '''
// ignore_for_file: type=lint
final Color kept = Color.red;
final Color alsoKept = Color.green;
''';
      expect(await scanSource(body), isEmpty);
    });

    test('a file level rule ignore keeps every finding', () async {
      const body = '''
// ignore_for_file: prefer_dot_shorthand
final Color kept = Color.red;
final Color alsoKept = Color.green;
''';
      expect(await scanSource(body), isEmpty);
    });

    test('a line ignore keeps its line and the line below', () async {
      const body = '''
final Color kept = Color.red; // ignore: prefer_dot_shorthand
// ignore: prefer_dot_shorthand
final Color alsoKept = Color.green;
''';
      expect(await scanSource(body), isEmpty);
    });

    test('the plugin prefixed ignore forms are honoured', () async {
      const body = '''
final Color kept = Color.red; // ignore: dot_shorthand/prefer_dot_shorthand
final Color alsoKept = Color.green; // ignore: dot_shorthand/prefer_dot_shorthand, unused_element
''';
      expect(await scanSource(body), isEmpty);
      const file = '''
// ignore_for_file: dot_shorthand/prefer_dot_shorthand
final Color kept = Color.red;
''';
      expect(await scanSource(file), isEmpty);
    });

    test('a line ignore elsewhere keeps nothing', () async {
      const body = '''
// ignore: prefer_dot_shorthand
final Color first = Color.red;

final Color second = Color.green;
''';
      expect(shorthands(await scanSource(body)), ['Color.green -> .green']);
    });

    test('generated sources are never read', () async {
      const source = '''
enum Color { red, green }

final Color value = Color.red;
''';
      final fixture = writeFixture({
        'thing.g.dart': source,
        'thing.gen.dart': source,
        'thing.freezed.dart': source,
        'thing.mocks.dart': source,
        'thing.dart': source,
      });
      addTearDown(fixture.dispose);
      final findings = await DotShorthandScan(paths: [fixture.lib]).scan();
      expect(shorthands(findings), ['Color.red -> .red']);
      expect(findings.single.path, endsWith('thing.dart'));
    });

    test('a file with a generated header is never rewritten', () async {
      const source = '''
// GENERATED CODE - DO NOT MODIFY BY HAND
enum Color { red, green }

final Color value = Color.red;
''';
      final fixture = writeFixture({'assets.dart': source});
      addTearDown(fixture.dispose);
      final scan = DotShorthandScan(paths: [fixture.lib]);
      expect(await scan.scan(), isEmpty);
      applyFindings(await scan.scan());
      expect(fixture.read('assets.dart'), source);
    });

    test(
      'a file below the dot shorthand language version is skipped',
      () async {
        const source = '''
// @dart=3.9
enum Color { red, green }

final Color value = Color.red;
''';
        final fixture = writeFixture({'old.dart': source});
        addTearDown(fixture.dispose);
        final scan = DotShorthandScan(paths: [fixture.lib]);
        expect(await scan.scan(), isEmpty);
        applyFindings(await scan.scan());
        expect(fixture.read('old.dart'), source);
      },
    );

    test('excluded paths are skipped', () async {
      const source = '''
enum Color { red, green }

final Color value = Color.red;
''';
      final fixture = writeFixture({
        'kept/thing.dart': source,
        'skipped/thing.dart': source,
        'vendor/thing.dart': source,
      });
      addTearDown(fixture.dispose);
      final findings = await DotShorthandScan(
        paths: [fixture.lib],
        exclude: ['**/skipped/**', 'lib/vendor/**'],
      ).scan();
      expect(findings, hasLength(1));
      expect(findings.single.path, endsWith(p.join('kept', 'thing.dart')));
    });
  });

  group('import cleanup', () {
    Future<Fixture> fixImports(Map<String, String> files) async {
      final fixture = writeFixture(files);
      addTearDown(fixture.dispose);
      final scan = DotShorthandScan(paths: [fixture.lib]);
      final findings = await scan.scan();
      final before = {
        for (final e in scan.unusedImports.entries) e.key: e.value.toList(),
      };
      final changed = applyFindings(findings);
      await scan.scan(changed);
      removeImports(newlyUnusedImports(before, scan.unusedImports));
      return fixture;
    }

    test('two directives on one line lose only the unused one', () async {
      final fixture = await fixImports({
        'tone.dart': 'enum Tone { light, dark }\n',
        'take.dart': "import 'tone.dart';\n\nvoid take(Tone tone) {}\n",
        'same_line.dart':
            "import 'tone.dart'; import 'take.dart';\n\n"
            'void call() => take(Tone.light);\n',
      });
      expect(
        fixture.read('same_line.dart'),
        "import 'take.dart';\n\nvoid call() => take(.light);\n",
      );
    });

    test('a rewrite in a part file cleans the import in its library', () async {
      final fixture = await fixImports({
        'tone.dart': 'enum Tone { light, dark }\n',
        'take.dart': "import 'tone.dart';\n\nvoid take(Tone tone) {}\n",
        'library.dart':
            "import 'take.dart';\nimport 'tone.dart';\n\n"
            "part 'piece.dart';\n",
        'piece.dart':
            "part of 'library.dart';\n\nvoid call() => take(Tone.light);\n",
      });
      expect(fixture.read('piece.dart'), contains('take(.light)'));
      expect(
        fixture.read('library.dart'),
        "import 'take.dart';\n\npart 'piece.dart';\n",
      );
    });
    test('a shown name the rewrite left unused is dropped', () async {
      final fixture = await fixImports({
        'tone.dart':
            'enum Tone { light, dark }\n\nclass Other {}\n\n'
            'void take(Tone tone) {}\n',
        'first.dart':
            "import 'tone.dart' show Tone, Other, take;\n\n"
            'void call() => take(Tone.light);\nOther other = Other();\n',
        'last.dart':
            "import 'tone.dart' show take, Tone;\n\n"
            'void call() => take(Tone.light);\n',
        'lines.dart':
            "import 'tone.dart'\n    show\n        take,\n        Tone;\n\n"
            'void call() => take(Tone.light);\n',
      });
      expect(
        fixture.read('first.dart'),
        "import 'tone.dart' show Other, take;\n\n"
        'void call() => take(.light);\nOther other = Other();\n',
      );
      expect(
        fixture.read('last.dart'),
        "import 'tone.dart' show take;\n\nvoid call() => take(.light);\n",
      );
      expect(
        fixture.read('lines.dart'),
        "import 'tone.dart'\n    show\n        take;\n\n"
        'void call() => take(.light);\n',
      );
    });

    test('a shown name that was already unused stays', () async {
      final fixture = await fixImports({
        'tone.dart':
            'enum Tone { light, dark }\n\nclass Other {}\n\n'
            'void take(Tone tone) {}\n',
        'kept.dart':
            "import 'tone.dart' show take, Tone, Other;\n\n"
            'void call() => take(Tone.light);\n',
      });
      expect(
        fixture.read('kept.dart'),
        "import 'tone.dart' show take, Other;\n\n"
        'void call() => take(.light);\n',
      );
    });

    test('a show list left wholly unused loses the import', () async {
      final fixture = await fixImports({
        'tone.dart': 'enum Tone { light, dark }\n',
        'take.dart': "import 'tone.dart';\n\nvoid take(Tone tone) {}\n",
        'whole.dart':
            "import 'take.dart';\nimport 'tone.dart' show Tone;\n\n"
            'void call() => take(Tone.light);\n',
      });
      expect(
        fixture.read('whole.dart'),
        "import 'take.dart';\n\nvoid call() => take(.light);\n",
      );
    });
  });

  group('command line', () {
    test(
      'scans, fixes in place and rescans',
      timeout: const Timeout(Duration(minutes: 3)),
      () async {
        const body = '''
final Color value = Color.red;
final Color kept = Color.green; // dot_shorthand: ignore
''';
        final fixture = writeFixture({
          'fixture.dart': fixtureSource(body),
          'tone.dart': 'enum Tone { light, dark }\n',
          'take.dart': "import 'tone.dart';\n\nvoid take(Tone tone) {}\n",
          'other.dart': '''
import 'dart:async';
import 'take.dart';
import 'tone.dart';

void call() => take(Tone.light);
''',
        });
        addTearDown(fixture.dispose);
        final entrypoint = p.join(
          Directory.current.path,
          'bin',
          'dot_shorthand.dart',
        );

        Future<ProcessResult> run(List<String> arguments) => Process.run(
          Platform.resolvedExecutable,
          ['run', entrypoint, ...arguments],
        );

        final scan = await run([fixture.lib]);
        expect(scan.exitCode, 1, reason: scan.stderr.toString());
        expect(scan.stdout, contains('Color.red -> .red'));
        expect(scan.stdout, contains('Tone.light -> .light'));
        expect(scan.stdout, contains('2 finding(s)'));
        expect(scan.stdout, isNot(contains('Color.green')));

        final asJson = await run(['--format', 'json', fixture.lib]);
        expect(asJson.exitCode, 1, reason: asJson.stderr.toString());
        final report = jsonDecode(asJson.stdout as String) as Map;
        expect(report.keys, ['findings', 'changedFiles', 'removedImports']);
        expect(report['changedFiles'], isEmpty);
        expect(report['removedImports'], isEmpty);
        final decoded = (report['findings'] as List)
            .cast<Map<String, Object?>>();
        expect(decoded, hasLength(2));
        final first = decoded.first;
        expect(first.keys, [
          'path',
          'line',
          'column',
          'source',
          'shorthand',
          'contextType',
        ]);
        expect(first['path'], endsWith('fixture.dart'));
        expect(first['line'], isA<int>());
        expect(first['column'], isA<int>());
        expect(first['source'], 'Color.red');
        expect(first['shorthand'], '.red');
        expect(first['contextType'], 'Color');

        final fix = await run(['--fix', fixture.lib]);
        expect(fix.exitCode, 0, reason: fix.stderr.toString());
        expect(fix.stdout, contains('rewritten '));
        expect(fix.stdout, contains('other.dart'));
        expect(fix.stdout, contains("removed import 'tone.dart'"));
        expect(
          fix.stdout,
          contains('2 file(s) rewritten, 0 finding(s) remaining'),
        );
        expect(
          fixture.read('fixture.dart'),
          contains('final Color value = .red;'),
        );
        expect(
          fixture.read('other.dart'),
          "import 'dart:async';\nimport 'take.dart';\n\nvoid call() => take(.light);\n",
          reason:
              'the import the rewrite made redundant goes, the one that '
              'was already unused stays',
        );

        final rescan = await run([fixture.lib]);
        expect(rescan.exitCode, 0, reason: rescan.stderr.toString());
        expect(rescan.stdout, contains('no finding'));

        final again = await run(['--fix', fixture.lib]);
        expect(again.exitCode, 0);
        expect(again.stdout, contains('nothing to rewrite'));

        final bad = await run(['--bogus']);
        expect(bad.exitCode, 64);
        expect(bad.stderr, contains('--fix'));

        final version = await run(['--version']);
        expect(
          version.stdout.toString().trim(),
          matches(RegExp(r'^\d+\.\d+\.\d+$')),
        );
      },
    );
  });
}
