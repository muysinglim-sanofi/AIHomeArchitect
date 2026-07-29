import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/services.dart' show rootBundle;
// XFile is re-exported by flutter_image_compress (via cross_file); importing
// image_picker as well would be an unnecessary_import.
import 'package:flutter_image_compress/flutter_image_compress.dart';

import 'ayden_image_source.dart';

/// Batch 1B — the single platform boundary for turning a picked file / asset
/// into an [AydenImageSource] and compressing its bytes for upload.
///
/// This is the ONLY place that touches `image_picker`/`flutter_image_compress`;
/// the hot screens (upload/chat) and the router carry [AydenImageSource] and
/// bytes, never `dart:io File` and never a filesystem path.
///
/// Web-safety: this layer never constructs `File`, never uses
/// `Directory.systemTemp`, and never calls `compressWithFile` on web.

/// Compression parameters. Batch 1B preserves the EXACT values the previous
/// mobile path used (`chat_screen._compressSource`): quality 85, 1920px cap,
/// JPEG, EXIF dropped. Applied identically on IO and web so the logical upload
/// input is unchanged across platforms.
class ImageCompressParams {
  const ImageCompressParams({
    this.quality = 85,
    this.minWidth = 1920,
    this.minHeight = 1920,
    this.format = CompressFormat.jpeg,
    this.keepExif = false,
  });

  final int quality;
  final int minWidth;
  final int minHeight;
  final CompressFormat format;
  final bool keepExif;
}

/// Injectable compressor seam (tests provide a fake). Returns compressed bytes,
/// or null on failure. The pipeline also catches throws defensively so the
/// raw-bytes fallback always holds.
typedef ImageCompressor = Future<Uint8List?> Function(
  AydenImageSource source,
  ImageCompressParams params,
);

class ImagePipeline {
  const ImagePipeline._();

  /// Pure platform decision: use the native file-path compressor ONLY on IO and
  /// when a non-empty native path is available. Extracted so the web-never-uses-
  /// compressWithFile rule is deterministically testable.
  static bool shouldUseNativeCompression({
    required bool isWeb,
    required String? nativePath,
  }) =>
      !isWeb && nativePath != null && nativePath.isNotEmpty;

  /// Adapter: `image_picker` [XFile] → [AydenImageSource]. Bytes are read here
  /// via the cross-platform `readAsBytes()`. The native path is retained only on
  /// IO; on web `XFile.path` is a blob URL and is deliberately dropped.
  static Future<AydenImageSource> fromXFile(XFile file) async {
    final bytes = await file.readAsBytes();
    return AydenImageSource(
      bytes: bytes,
      filename: file.name,
      mimeType: file.mimeType,
      nativePath: kIsWeb ? null : file.path,
    );
  }

  /// Adapter: bundled asset → [AydenImageSource]. Bytes stay in memory — no temp
  /// file, no `Directory.systemTemp` (the previous IO-only example flow).
  static Future<AydenImageSource> fromAsset(String assetPath) async {
    final data = await rootBundle.load(assetPath);
    final bytes =
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    final base = assetPath.split('/').last;
    return AydenImageSource(
      bytes: bytes,
      filename: base.isEmpty ? 'example.jpg' : base,
      mimeType: 'image/jpeg',
      nativePath: null,
    );
  }

  /// Compress [source] for upload with a GUARANTEED non-destructive fallback:
  /// on any throw / null / empty result the ORIGINAL bytes are returned (never
  /// empty). On IO with a native path this uses `compressWithFile` (identical to
  /// the previous mobile behaviour); otherwise (incl. all of web) it uses the
  /// in-memory `compressWithList`.
  static Future<Uint8List> compressForUpload(
    AydenImageSource source, {
    ImageCompressor? compressor,
    ImageCompressParams params = const ImageCompressParams(),
  }) async {
    final c = compressor ?? _defaultCompressor;
    try {
      final out = await c(source, params);
      if (out != null && out.isNotEmpty) return out;
    } catch (e) {
      debugPrint('[ImagePipeline] compress failed (non-fatal, using raw): $e');
    }
    return source.bytes;
  }

  static Future<Uint8List?> _defaultCompressor(
    AydenImageSource source,
    ImageCompressParams p,
  ) {
    if (shouldUseNativeCompression(
        isWeb: kIsWeb, nativePath: source.nativePath)) {
      // MOBILE fast path — byte-for-byte the same call the previous
      // `_compressSource(imageFile.path)` made.
      return FlutterImageCompress.compressWithFile(
        source.nativePath!,
        quality: p.quality,
        minWidth: p.minWidth,
        minHeight: p.minHeight,
        format: p.format,
        keepExif: p.keepExif,
      );
    }
    // WEB (and IO without a native path) — in-memory compression.
    return FlutterImageCompress.compressWithList(
      source.bytes,
      quality: p.quality,
      minWidth: p.minWidth,
      minHeight: p.minHeight,
      format: p.format,
      keepExif: p.keepExif,
    );
  }
}
