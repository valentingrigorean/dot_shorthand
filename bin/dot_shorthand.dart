import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:dot_shorthand/dot_shorthand.dart';
import 'package:path/path.dart' as p;

const _version = '1.1.0';

const _synopsis =
    'dot_shorthand [--fix] [--exclude <glob>] [--format json] [<paths>...]';

Future<void> main(List<String> arguments) async {
  exitCode = await _run(arguments);
}

Future<int> _run(List<String> arguments) async {
  final parser = ArgParser()
    ..addFlag(
      'fix',
      negatable: false,
      help:
          'Rewrite every finding in place, rescan the changed files and drop '
          'the imports the rewrite left unused.',
    )
    ..addMultiOption(
      'exclude',
      help: 'Glob of paths to skip, relative to the package root; repeatable.',
    )
    ..addOption(
      'format',
      allowed: ['text', 'json'],
      defaultsTo: 'text',
      help: 'Report shape.',
    )
    ..addFlag('version', negatable: false, help: 'Print the version.')
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Print this help.');

  final ArgResults options;
  try {
    options = parser.parse(arguments);
  } on FormatException catch (e) {
    stderr
      ..writeln(e.message)
      ..writeln()
      ..writeln(_synopsis)
      ..writeln(parser.usage);
    return 64;
  }
  if (options.flag('help')) {
    stdout
      ..writeln('dot_shorthand $_version')
      ..writeln(
        'Rewrites Color.red style references to the .red dot '
        'shorthand form where the context type already supplies it.',
      )
      ..writeln()
      ..writeln(_synopsis)
      ..writeln(parser.usage)
      ..writeln()
      ..writeln(
        'Paths default to the current directory. Exit code 0 means '
        'no finding, 1 means findings, 2 means a path does not exist, '
        '64 means a bad flag.',
      );
    return 0;
  }
  if (options.flag('version')) {
    stdout.writeln(_version);
    return 0;
  }

  final paths = options.rest.isEmpty ? [Directory.current.path] : options.rest;
  final missing = paths.where(
    (path) => !Directory(path).existsSync() && !File(path).existsSync(),
  );
  if (missing.isNotEmpty) {
    stderr.writeln('no such path: ${missing.join(', ')}');
    return 2;
  }

  final scan = DotShorthandScan(
    paths: paths,
    exclude: options.multiOption('exclude'),
  );
  final json = options.option('format') == 'json';
  var findings = await scan.scan();

  var changed = const <String>[];
  var imports = const <UnusedImport>[];
  if (options.flag('fix') && findings.isNotEmpty) {
    final before = {
      for (final e in scan.unusedImports.entries) e.key: e.value.toList(),
    };
    changed = applyFindings(findings);
    findings = await scan.scan(changed);
    imports = newlyUnusedImports(before, scan.unusedImports);
    if (imports.isNotEmpty) {
      findings = await scan.scan(removeImports(imports));
    }
  }

  if (json) {
    stdout.writeln(
      const JsonEncoder.withIndent('  ').convert({
        'findings': findings.map(_encode).toList(),
        'changedFiles': changed.map(_relative).toList(),
        'removedImports': [
          for (final i in imports) {'path': _relative(i.path), 'uri': i.uri},
        ],
      }),
    );
  } else {
    for (final file in changed) {
      stdout.writeln('rewritten ${_relative(file)}');
    }
    for (final import in imports) {
      stdout.writeln(
        "removed import '${import.uri}' ${_relative(import.path)}",
      );
    }
    for (final finding in findings) {
      stdout.writeln(_line(finding));
    }
    stdout.writeln(
      _summary(findings.length, changed.length, fix: options.flag('fix')),
    );
  }
  return findings.isEmpty ? 0 : 1;
}

String _summary(int findings, int changed, {required bool fix}) {
  if (!fix) return findings == 0 ? 'no finding' : '$findings finding(s)';
  if (changed == 0) return 'nothing to rewrite';
  return '$changed file(s) rewritten, $findings finding(s) remaining';
}

Map<String, Object?> _encode(Finding finding) => {
  'path': _relative(finding.path),
  'line': finding.line,
  'column': finding.column,
  'source': finding.source,
  'shorthand': finding.shorthand,
  'contextType': finding.contextType,
};

String _line(Finding finding) =>
    '${_relative(finding.path)}:${finding.line}:${finding.column} '
    '${finding.source} -> ${finding.shorthand} (context ${finding.contextType})';

String _relative(String path) => p.relative(path);
