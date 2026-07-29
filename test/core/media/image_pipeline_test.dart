// Batch 1B — byte-identity / contract tests for the web-safe image pipeline.
//
// These prove the transport refactor does NOT alter the logical image contract:
// bytes are preserved exactly, metadata is preserved, and compression always
// falls back to the original bytes on failure. Deterministic — uses injected
// fake compressors, no real plugin, no network, no filesystem.

import 'dart:typed_data';

import 'package:ai_home_architect/core/media/ayden_image_source.dart';
import 'package:ai_home_architect/core/media/image_pipeline.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart'
    show CompressFormat;
import 'package:flutter_test/flutter_test.dart';

Uint8List _b(List<int> v) => Uint8List.fromList(v);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const original = [1, 2, 3, 4, 5];

  AydenImageSource makeSource({String? nativePath}) => AydenImageSource(
        bytes: _b(original),
        filename: 'source_123.jpg',
        mimeType: 'image/jpeg',
        nativePath: nativePath,
      );

  group('AydenImageSource — byte + metadata preservation', () {
    test('bytes are held exactly', () {
      final s = makeSource();
      expect(s.bytes, equals(_b(original)));
    });

    test('metadata is preserved; nativePath optional', () {
      final s = makeSource(nativePath: '/tmp/x.jpg');
      expect(s.filename, 'source_123.jpg');
      expect(s.mimeType, 'image/jpeg');
      expect(s.nativePath, '/tmp/x.jpg');

      final web = makeSource(); // no native path (web)
      expect(web.nativePath, isNull);
    });

    test('copyWith keeps unspecified fields', () {
      final s = makeSource(nativePath: '/tmp/x.jpg')
          .copyWith(filename: 'renamed.jpg');
      expect(s.filename, 'renamed.jpg');
      expect(s.bytes, equals(_b(original)));
      expect(s.nativePath, '/tmp/x.jpg');
    });
  });

  group('AydenImageSource.tryFrom — safe router extra (no blind cast)', () {
    test('valid image object is returned', () {
      final s = makeSource();
      expect(AydenImageSource.tryFrom(s), same(s));
    });
    test('wrong extra type yields null (does not throw)', () {
      expect(AydenImageSource.tryFrom('not-an-image'), isNull);
      expect(AydenImageSource.tryFrom(42), isNull);
      expect(AydenImageSource.tryFrom(null), isNull);
    });
  });

  group('ImagePipeline.shouldUseNativeCompression — platform decision', () {
    test('web never uses the native file path (compressWithFile)', () {
      expect(
        ImagePipeline.shouldUseNativeCompression(
            isWeb: true, nativePath: '/real/path.jpg'),
        isFalse,
      );
    });
    test('IO with a native path uses it', () {
      expect(
        ImagePipeline.shouldUseNativeCompression(
            isWeb: false, nativePath: '/real/path.jpg'),
        isTrue,
      );
    });
    test('IO without a native path falls back to bytes', () {
      expect(
        ImagePipeline.shouldUseNativeCompression(
            isWeb: false, nativePath: null),
        isFalse,
      );
      expect(
        ImagePipeline.shouldUseNativeCompression(isWeb: false, nativePath: ''),
        isFalse,
      );
    });
  });

  group('ImagePipeline.compressForUpload — non-destructive fallback', () {
    test('successful compression returns the compressed bytes', () async {
      final out = await ImagePipeline.compressForUpload(
        makeSource(),
        compressor: (s, p) async => _b([9, 9, 9]),
      );
      expect(out, equals(_b([9, 9, 9])));
    });

    test('compressor throws → original bytes returned', () async {
      final out = await ImagePipeline.compressForUpload(
        makeSource(),
        compressor: (s, p) async => throw StateError('boom'),
      );
      expect(out, equals(_b(original)));
    });

    test('compressor returns null → original bytes returned', () async {
      final out = await ImagePipeline.compressForUpload(
        makeSource(),
        compressor: (s, p) async => null,
      );
      expect(out, equals(_b(original)));
    });

    test('compressor returns empty → original bytes returned (never empty)',
        () async {
      final out = await ImagePipeline.compressForUpload(
        makeSource(),
        compressor: (s, p) async => _b(const []),
      );
      expect(out, equals(_b(original)));
      expect(out, isNotEmpty);
    });

    test('the default params match the preserved mobile values', () async {
      late ImageCompressParams seen;
      await ImagePipeline.compressForUpload(
        makeSource(),
        compressor: (s, p) async {
          seen = p;
          return _b([1]);
        },
      );
      expect(seen.quality, 85);
      expect(seen.minWidth, 1920);
      expect(seen.minHeight, 1920);
      expect(seen.format, CompressFormat.jpeg);
      expect(seen.keepExif, isFalse);
    });
  });

  group('ImagePipeline.fromAsset — bundled bytes, no temp file', () {
    test('creates a valid image object from a bundled asset', () async {
      // Real bundled example asset (declared in pubspec assets/examples/).
      final src = await ImagePipeline.fromAsset('assets/examples/kitchen.jpg');
      expect(src.bytes, isNotEmpty);
      expect(src.filename, 'kitchen.jpg');
      expect(src.nativePath, isNull); // never a temp file
      expect(src.mimeType, 'image/jpeg');
    });
  });
}
