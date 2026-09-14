import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

import '../../dot_shorthand.dart';

class PreferDotShorthandRule extends AnalysisRule {
  static const LintCode code = LintCode(
    'prefer_dot_shorthand',
    "The context type already supplies '{0}'; use '{1}'.",
    correctionMessage: "Try replacing '{0}' with '{1}'.",
    uniqueName: 'LintCode.prefer_dot_shorthand',
  );

  PreferDotShorthandRule()
    : super(
        name: 'prefer_dot_shorthand',
        description:
            'A member named through its type where the context type '
            'already supplies it can use the dot shorthand form.',
      );

  @override
  DiagnosticCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    if (!context.isFeatureEnabled(.dot_shorthands)) return;
    registry.addCompilationUnit(this, _Visitor(this, context));
  }
}

class _Visitor extends SimpleAstVisitor<void> {
  _Visitor(this.rule, this.context);

  final AnalysisRule rule;
  final RuleContext context;

  @override
  void visitCompilationUnit(CompilationUnit node) {
    final unit = context.currentUnit;
    if (unit == null || unit.unit != node) return;
    final visitor = ShorthandVisitor.forUnit(
      unit: node,
      content: unit.content,
      path: unit.file.path,
    );
    node.accept(visitor);
    for (final finding in visitor.findings) {
      if (isIgnored(unit.content, node.lineInfo, finding)) continue;
      rule.reportAtOffset(
        finding.offset,
        finding.end - finding.offset,
        arguments: [finding.source, finding.shorthand],
      );
    }
  }
}
