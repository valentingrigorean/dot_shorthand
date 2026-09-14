import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analysis_server_plugin/edit/dart/dart_fix_kind_priority.dart';
import 'package:analyzer/source/source_range.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';

import '../shorthand_visitor.dart';

class ConvertToDotShorthandFix extends ResolvedCorrectionProducer {
  static const kind = FixKind(
    'dot_shorthand.fix.convertToDotShorthand',
    DartFixKindPriority.standard,
    'Convert to dot shorthand',
  );

  ConvertToDotShorthandFix({required super.context});

  @override
  CorrectionApplicability get applicability => .singleLocation;

  @override
  FixKind get fixKind => kind;

  @override
  Future<void> compute(ChangeBuilder builder) async {
    final offset = diagnosticOffset;
    if (offset == null) return;
    final visitor = ShorthandVisitor(unitResult);
    unitResult.unit.accept(visitor);
    for (final finding in visitor.findings) {
      if (finding.offset != offset) continue;
      await builder.addDartFileEdit(file, (builder) {
        builder.addDeletion(
          SourceRange(
            finding.deleteStart,
            finding.deleteEnd - finding.deleteStart,
          ),
        );
      });
      return;
    }
  }
}
