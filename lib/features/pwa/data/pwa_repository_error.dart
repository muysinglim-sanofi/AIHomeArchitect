/// Batch 3.0 — typed data-layer errors (§25).
///
/// Every persistence operation either returns domain data or throws a
/// [PwaRepositoryError] with a category. Raw database/network exceptions are
/// never surfaced to widgets. Messages must not carry secrets, signed URLs or
/// full sensitive paths.
library;

enum PwaErrorKind {
  /// Environment / credentials / boot-guard failure — never a silent fallback.
  configuration,
  unauthorized,
  network,
  timeout,
  validation,
  notFound,
  conflict,
  storage,
  serialization,
  unknown,
}

class PwaRepositoryError implements Exception {
  const PwaRepositoryError(this.kind, this.message, {this.cause});

  final PwaErrorKind kind;
  final String message;

  /// Optional low-level cause. NOT surfaced to the UI; for staging logs only.
  final Object? cause;

  bool get isRetryable =>
      kind == PwaErrorKind.network ||
      kind == PwaErrorKind.timeout ||
      kind == PwaErrorKind.storage;

  const PwaRepositoryError.configuration(String message)
    : this(PwaErrorKind.configuration, message);
  const PwaRepositoryError.validation(String message)
    : this(PwaErrorKind.validation, message);
  const PwaRepositoryError.serialization(String message)
    : this(PwaErrorKind.serialization, message);
  const PwaRepositoryError.notFound(String message)
    : this(PwaErrorKind.notFound, message);
  const PwaRepositoryError.conflict(String message)
    : this(PwaErrorKind.conflict, message);

  @override
  String toString() => 'PwaRepositoryError(${kind.name}): $message';
}
