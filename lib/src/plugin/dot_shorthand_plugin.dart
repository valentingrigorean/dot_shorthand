import 'package:analysis_server_plugin/plugin.dart';
import 'package:analysis_server_plugin/registry.dart';

import 'convert_to_dot_shorthand_fix.dart';
import 'prefer_dot_shorthand_rule.dart';

class DotShorthandPlugin extends Plugin {
  @override
  String get name => 'dot_shorthand';

  @override
  void register(PluginRegistry registry) {
    registry
      ..registerWarningRule(PreferDotShorthandRule())
      ..registerFixForRule(
        PreferDotShorthandRule.code,
        ConvertToDotShorthandFix.new,
      );
  }
}
