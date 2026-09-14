# Example

`lib/dot_shorthand_example.dart` holds eight places that can drop their type name, one already in shorthand form, one kept by an ignore comment, and two unnamed constructor calls the tool leaves alone.

List them:

```sh
dart pub global activate dot_shorthand
dot_shorthand example/lib
```

Rewrite them:

```sh
dot_shorthand --fix example/lib
```

The `analysis_options.yaml` in this directory enables the editor plugin, so the same places show as diagnostics with a quick fix.
