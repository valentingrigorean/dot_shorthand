/// Entry point loaded by the analysis server.
///
/// The server reads [plugin] from this library when a project lists
/// `dot_shorthand` under `plugins:` in its analysis options.
library;

import 'src/plugin/dot_shorthand_plugin.dart';

/// The plugin instance the analysis server registers.
final plugin = DotShorthandPlugin();
