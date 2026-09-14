import 'dart:async';
import 'dart:io';

import 'package:analysis_server_plugin/src/correction/fix_generators.dart';
import 'package:analysis_server_plugin/src/plugin_server.dart';
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:analyzer_plugin/channel/channel.dart';
import 'package:analyzer_plugin/protocol/protocol.dart' as protocol;
import 'package:analyzer_plugin/protocol/protocol_constants.dart' as protocol;
import 'package:analyzer_plugin/protocol/protocol_generated.dart' as protocol;
import 'package:analyzer_plugin/src/protocol/protocol_internal.dart'
    as protocol;
import 'package:async/async.dart';
import 'package:dot_shorthand/src/plugin/convert_to_dot_shorthand_fix.dart';
import 'package:dot_shorthand/src/plugin/dot_shorthand_plugin.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support.dart';

const body = '''
final Color miss = Color.red;
final Color ignored = Color.green; // dot_shorthand: ignore
final Plain unnamed = Plain(1);
final Insets second = Insets.zero;
final Insets spread = Insets.all(
  9,
);
''';

void main() {
  late Fixture fixture;
  late Directory byteStore;
  late _Channel channel;
  late PluginServer server;
  late String file;
  late String source;

  setUp(() async {
    fixture = writeFixture({'fixture.dart': '$preamble\n$body'});
    File(p.join(fixture.root.path, 'analysis_options.yaml'))
        .writeAsStringSync('''
plugins:
  dot_shorthand:
    path: ${p.current}
''');
    byteStore = Directory.systemTemp.createTempSync('dot_shorthand_bytes_');
    file = fixture.path('fixture.dart');
    source = fixture.read('fixture.dart');
    channel = _Channel();
    server = PluginServer(
      resourceProvider: PhysicalResourceProvider.INSTANCE,
      plugins: [DotShorthandPlugin()],
    );
    await server.initialize();
    server.start(channel);
    await server.handlePluginVersionCheck(
      protocol.PluginVersionCheckParams(
        byteStore.path,
        p.dirname(p.dirname(Platform.resolvedExecutable)),
        '0.0.1',
      ),
    );
  });

  tearDown(() {
    registeredFixGenerators
      ..clearLintProducers()
      ..clearWarningProducers();
    fixture.dispose();
    byteStore.deleteSync(recursive: true);
  });

  Future<protocol.AnalysisErrorsParams> analyze() async {
    final errors = StreamQueue(
      channel.notifications
          .where((n) => n.event == protocol.ANALYSIS_NOTIFICATION_ERRORS)
          .map(protocol.AnalysisErrorsParams.fromNotification)
          .where((params) => params.file == file),
    );
    final root = protocol.ContextRoot(fixture.root.path, []);
    await channel.sendRequest(protocol.AnalysisSetContextRootsParams([root]));
    await channel.sendRequest(
      protocol.AnalysisSetAnalysisRootsParams([root.root], []),
    );
    return errors.next;
  }

  test('reports each miss and nothing else', () async {
    final params = await analyze();
    expect(params.errors, hasLength(3));
    final first = params.errors.first;
    expect(first.code, 'prefer_dot_shorthand');
    expect(first.location.offset, source.indexOf('Color.red'));
    expect(first.location.length, 'Color.red'.length);
    expect(first.message, contains("use '.red'"));
    final second = params.errors[1];
    expect(second.location.offset, source.lastIndexOf('Insets.zero'));
    expect(second.location.length, 'Insets.zero'.length);
  });

  test('a generated header file gets no diagnostic', () async {
    final generated = fixture.path('generated.dart');
    File(generated).writeAsStringSync(
      '// GENERATED CODE - DO NOT MODIFY BY HAND\n$preamble\n$body',
    );
    final errors = StreamQueue(
      channel.notifications
          .where((n) => n.event == protocol.ANALYSIS_NOTIFICATION_ERRORS)
          .map(protocol.AnalysisErrorsParams.fromNotification)
          .where((params) => params.file == generated),
    );
    final root = protocol.ContextRoot(fixture.root.path, []);
    await channel.sendRequest(protocol.AnalysisSetContextRootsParams([root]));
    await channel.sendRequest(
      protocol.AnalysisSetAnalysisRootsParams([root.root], []),
    );
    expect((await errors.next).errors, isEmpty);
  });

  test('the range of a multi-line expression covers all of it', () async {
    final params = await analyze();
    const expression = 'Insets.all(\n  9,\n)';
    final offset = source.indexOf(expression);
    final reported = params.errors.singleWhere(
      (error) => error.location.offset == offset,
    );
    expect(reported.location.length, expression.length);
  });

  test('offers the rewrite as a fix that deletes the type name', () async {
    await analyze();
    final offset = source.indexOf('Color.red');
    final result = await server.handleEditGetFixes(
      protocol.EditGetFixesParams(file, offset),
    );
    final single = result.fixes.single.fixes.singleWhere(
      (fix) => fix.change.id == ConvertToDotShorthandFix.kind.id,
    );
    expect(single.change.message, 'Convert to dot shorthand');
    final edit = single.change.edits.single.edits.single;
    expect(edit.offset, offset);
    expect(edit.length, 'Color'.length);
    expect(edit.replacement, isEmpty);
    final fixed = source.replaceRange(
      edit.offset,
      edit.offset + edit.length,
      '',
    );
    expect(fixed, contains('final Color miss = .red;'));

    expect(fixed, contains('Color.green; // dot_shorthand: ignore'));
    expect(fixed, contains('Plain(1)'));
    expect(fixed, contains('Insets.zero'));
  });

  test(
    'the fix of a multi-line expression deletes only the type name',
    () async {
      await analyze();
      final offset = source.indexOf('Insets.all(\n');
      final result = await server.handleEditGetFixes(
        protocol.EditGetFixesParams(file, offset),
      );
      final single = result.fixes.single.fixes.singleWhere(
        (fix) => fix.change.id == ConvertToDotShorthandFix.kind.id,
      );
      final edit = single.change.edits.single.edits.single;
      expect(edit.offset, offset);
      expect(edit.length, 'Insets'.length);
      final fixed = source.replaceRange(
        edit.offset,
        edit.offset + edit.length,
        '',
      );
      expect(fixed, contains('final Insets spread = .all(\n  9,\n);'));
    },
  );
}

class _Channel implements PluginCommunicationChannel {
  final _completers = <String, Completer<protocol.Response>>{};
  final _notifications = StreamController<protocol.Notification>.broadcast();
  void Function(protocol.Request)? _onRequest;
  var _nextId = 0;

  Stream<protocol.Notification> get notifications => _notifications.stream;

  @override
  void close() {}

  @override
  void listen(
    void Function(protocol.Request request)? onRequest, {
    void Function()? onDone,
    Function? onError,
    Function? onNotification,
  }) {
    _onRequest = onRequest;
  }

  @override
  void sendNotification(protocol.Notification notification) {
    _notifications.add(notification);
  }

  Future<protocol.Response> sendRequest(protocol.RequestParams params) {
    final request = params.toRequest('${_nextId++}');
    final completer = Completer<protocol.Response>();
    _completers[request.id] = completer;
    _onRequest!(request);
    return completer.future;
  }

  @override
  void sendResponse(protocol.Response response) {
    _completers.remove(response.id)?.complete(response);
  }
}
