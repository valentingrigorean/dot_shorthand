## 1.1.0

- A static const on the context type that holds the same object is rewritten too: `padding: EdgeInsets.zero` becomes `padding: .zero` through `EdgeInsetsGeometry.zero`.
- `--fix` removes the imports the rewrite left unused or unnecessary.
- The command line honours `// ignore: dot_shorthand/prefer_dot_shorthand`, the plugin-prefixed form the analyzer accepts.
- `--format json` has one shape in scan and fix mode: `findings`, `changedFiles`, `removedImports`.
- Fix mode ends with a summary line, a bad flag prints usage and exits 64, and `--version` prints the version.

## 1.0.0

- `dot_shorthand` command with scan and `--fix` modes.
- `prefer_dot_shorthand` analyzer rule with a quick fix.
