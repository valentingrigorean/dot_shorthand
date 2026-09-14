# dot_shorthand

[![pub package](https://img.shields.io/pub/v/dot_shorthand.svg)](https://pub.dev/packages/dot_shorthand)
[![pub points](https://img.shields.io/pub/points/dot_shorthand)](https://pub.dev/packages/dot_shorthand/score)
[![CI](https://github.com/valentingrigorean/dot_shorthand/actions/workflows/ci.yml/badge.svg)](https://github.com/valentingrigorean/dot_shorthand/actions/workflows/ci.yml)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Migrate a Dart or Flutter codebase to [dot shorthands](https://dart.dev/language/dot-shorthands), in bulk from the command line or one quick fix at a time in the editor.

```dart
// before
Column(mainAxisAlignment: MainAxisAlignment.center, children: children);
Text(label, textAlign: TextAlign.center);
Future<void>.delayed(Duration.zero);
final Status status = Status.idle;

// after
Column(mainAxisAlignment: .center, children: children);
Text(label, textAlign: .center);
Future<void>.delayed(.zero);
final Status status = .idle;
```

Dart 3.10 lets you write `.red` instead of `Color.red` wherever the context type already says `Color`.
The SDK has no migration for it, so existing code keeps the long form.
This package finds every place where the context type makes the shorthand legal and rewrites it.

## Command line

```sh
dart pub global activate dot_shorthand

dot_shorthand lib test          # list every place that can use the shorthand
dot_shorthand --fix lib test    # rewrite them, rescan, drop imports and shown names that became unused
```

Scan first. The scan is the dry run: it changes nothing and exits with code 1 when there is anything to rewrite, so it can also gate CI.

| Flag | Effect |
|---|---|
| `--fix` | Rewrites every finding in place, rescans the changed files, and drops the imports, or the names in their `show` lists, the rewrite left unused or unnecessary |
| `--exclude <glob>` | Skips matching paths, relative to the package root; repeatable |
| `--format json` | Prints one object: `findings` (each with `path`, `line`, `column`, `source`, `shorthand`, `contextType`), `changedFiles` (paths), `removedImports` (each with `path`, `uri`, `name`; `name` is null when the whole import went); paths are relative to the working directory |
| `--version` | Prints the version |

Paths default to the current directory. Each path is analysed inside the nearest package above it (the closest `pubspec.yaml`), so context types resolve the same way they do in the editor.

Exit codes: 0 when nothing is left to rewrite, 1 when findings remain, 2 when a path does not exist, 64 on a bad flag.

## Editor plugin

Add the plugin to the `analysis_options.yaml` at the root of a package and restart the analysis server:

```yaml
plugins:
  dot_shorthand: ^1.1.0
```

The rule `prefer_dot_shorthand` reports each place as a diagnostic, with a quick fix that drops the type name.
`dart analyze` reports the same diagnostics.
As of Dart 3.13, `dart fix --apply` does not run plugin fixes; use the command line `--fix` for bulk rewrites.

A local checkout works too:

```yaml
plugins:
  dot_shorthand:
    path: ../dot_shorthand
```

## Suppressing findings

| Comment | Scope |
|---|---|
| `// ignore: prefer_dot_shorthand` on the line or the line above | One finding |
| `// ignore: dot_shorthand/prefer_dot_shorthand` | Same, in the plugin-prefixed form the analyzer also accepts |
| `// ignore_for_file: prefer_dot_shorthand` | The whole file |
| `// dot_shorthand: ignore` on the line | Every finding on that line, with or without the plugin loaded |

The command line and the plugin honour all four.

## What it rewrites

<details>
<summary>Context kinds the tool understands</summary>

| Kind | Example |
|---|---|
| Default parameter values | `this.status = Status.initial` |
| Named and positional arguments | `take(Color.red)` |
| Typed variable and field declarations | `final Color c = Color.red` |
| Plain assignments | `c = Color.red` |
| Constructor field initializers | `: _color = Color.red` |
| Returns with a declared return type | `Color pick() => Color.red` |
| Equality (`==` and `!=`) against a typed left side | `if (c == Color.red)` |
| Switch cases and if-case patterns | `case Color.red:` |
| Conditional branches in a typed position | `flag ? Color.red : Color.green` |
| Collection elements with a known element type | `final List<Color> all = [Color.red]` |
| Type arguments fixed by the receiver | `target.add(Color.red)` where `target: List<Color>` |
| Fields of a generic class | `slot.value = Color.red` where `slot: Slot<Color>` |
| Members the context type forwards to the written type | `padding: EdgeInsets.all(8)` and `padding: EdgeInsets.zero` where the parameter is `EdgeInsetsGeometry`, because `EdgeInsetsGeometry.all` redirects to `EdgeInsets.all` and `EdgeInsetsGeometry.zero` holds the same object |

</details>

<details>
<summary>What it leaves alone, and why</summary>

| Kind | Reason |
|---|---|
| Unnamed constructors | `.new(...)` reads worse than the type name |
| A written type carrying type arguments | `Foo<int>.bar()` cannot drop the type name and keep the arguments |
| A static member reached through a supertype | Only rewritten when the supertype has a redirecting constructor of that name, or a static const holding the same object |
| An argument whose type comes from the invocation's own type parameters | Inferred from the argument itself, no context to resolve against |
| `Enum.values` | The shorthand form does not apply |
| `??`, `await`, `yield`, cascade positions | The language does not read a context type there |
| Generated files | `.g.dart`, `.gen.dart`, `.freezed.dart`, `.mocks.dart`, and any file with a `GENERATED CODE - DO NOT MODIFY BY HAND` or `FILE GENERATED BY FLUTTERFIRE CLI` header in its first ten lines |
| Files below language version 3.10 | Dot shorthands do not exist there |

</details>

## Requirements

| What | Version |
|---|---|
| Dart SDK to run the tool or the plugin | 3.13.2 or later |
| Language version of the scanned files | 3.10 or later |

The plugin builds on `analysis_server_plugin`, which is pre-1.0 and tracks the SDK closely. CI runs the tests on the oldest supported SDK and on current stable.

## CI

```yaml
- run: dart pub global activate dot_shorthand
- run: dot_shorthand lib test
```

The step fails while anything is left to rewrite.

## Troubleshooting

| Symptom | Likely cause | What to check |
|---|---|---|
| `no such path` | A path argument does not exist | The paths passed on the command line |
| The scan finds nothing in a package that needs it | The package's language version is below 3.10 | The `sdk:` lower bound in `pubspec.yaml` |
| The plugin does not load in the editor | Plugin not configured or analysis server needs a restart | `analysis_options.yaml` sits at the package root; restart the analysis server; read the plugin log under `~/.dartServer/.plugin_manager/` |
| The scan is slow on a large repo | Every file is resolved | Narrow the paths, or `--exclude` generated and vendored trees |
| The compiler reports `dot_shorthand_missing_context` after a fix | The tool read a context type the compiler does not | Add `// dot_shorthand: ignore` to that line, restore the type name, and please open an issue with the snippet |

## Contributing

Issues and pull requests: https://github.com/valentingrigorean/dot_shorthand. Run `dart test` before sending one.

MIT license.
