// Run `dot_shorthand example/lib` from the package root to list the places
// below that can drop their type name, or `dot_shorthand --fix example/lib`
// to rewrite them.

enum Status { idle, loading, done }

class Insets {
  const Insets.all(this.value);
  const Insets.only({this.value = 0});

  static const zero = Insets.all(0);

  final int value;
}

class Badge {
  const Badge({
    this.status = Status.idle, // finding: .idle
    this.padding = Insets.zero, // finding: .zero
  });

  final Status status;
  final Insets padding;

  Badge withPadding(int value) => Badge(
    status: status,
    padding: Insets.only(value: value), // finding: .only(value: value)
  );
}

Status next(Status current) {
  if (current == Status.done) return Status.idle; // findings: .done, .idle
  switch (current) {
    case Status.idle: // finding: .idle
      return Status.loading; // finding: .loading
    default:
      return Status.done; // finding: .done
  }
}

final Status shorthand = .done;
final Status kept = Status.idle; // ignore: prefer_dot_shorthand
final Badge unnamed = Badge(); // unnamed constructors are left alone
