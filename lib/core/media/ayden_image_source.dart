import 'dart:typed_data';

/// Batch 1B — bytes-first image domain object.
///
/// Platform-agnostic transport for a user-selected / example image across the
/// app (navigation → preview → compression → upload). Intentionally free of
/// `dart:io`, `image_picker`, and any widget/backend types, so it behaves
/// identically on iOS, Android and Flutter Web and is pure-Dart testable.
///
/// Design contract (fixed by the product owner for Batch 1B):
///   • [bytes]      — MANDATORY, always present on every platform.
///   • [filename]   — MANDATORY (display / upload name).
///   • [mimeType]   — optional (present when the source reported one).
///   • [nativePath] — optional; set ONLY on IO for a faster native compression
///                    path. ALWAYS null on web. Never assume it exists.
class AydenImageSource {
  const AydenImageSource({
    required this.bytes,
    required this.filename,
    this.mimeType,
    this.nativePath,
  });

  /// Raw image bytes — the single source of truth, available on every platform.
  final Uint8List bytes;

  /// Display / upload filename (e.g. `source_1699999999.jpg`).
  final String filename;

  /// Optional MIME type when the source reported one (e.g. `image/jpeg`).
  final String? mimeType;

  /// Optional native filesystem path — IO-only optimization hint. Always null
  /// on web (a picker blob URL is NOT a usable native path).
  final String? nativePath;

  AydenImageSource copyWith({
    Uint8List? bytes,
    String? filename,
    String? mimeType,
    String? nativePath,
  }) =>
      AydenImageSource(
        bytes: bytes ?? this.bytes,
        filename: filename ?? this.filename,
        mimeType: mimeType ?? this.mimeType,
        nativePath: nativePath ?? this.nativePath,
      );

  /// Safe extraction from a loosely-typed navigation `extra` (go_router).
  /// Replaces the previous unsafe `state.extra as File?`: a wrong extra type
  /// yields null instead of a runtime cast crash.
  static AydenImageSource? tryFrom(Object? extra) =>
      extra is AydenImageSource ? extra : null;
}
