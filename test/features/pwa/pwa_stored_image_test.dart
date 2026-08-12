// PwaStoredImage — the ONE widget that turns a private Storage path into pixels.
//
// Written after a real defect: in the Architect, the "Vision 1" card rendered as
// a flat placeholder while the very same object signed and downloaded with HTTP
// 200 from the same session. The data was right, the wiring was right, and the
// image still never appeared.

import 'dart:async';

import 'package:ai_home_architect/features/pwa/application/pwa_controller.dart';
import 'package:ai_home_architect/features/pwa/data/pwa_image_url_resolver.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_stored_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _kPath = 'users/u1/projects/p1/generated/v1.jpg';

/// Records every signature it is asked for, and lets a test control WHEN each
/// one completes — which is how the ordering bug below becomes visible.
class _Signer {
  final List<String> calls = [];
  final List<Completer<String>> pending = [];
  bool autoComplete = true;

  Future<String> sign(String path, int expiresIn) {
    calls.add(path);
    if (autoComplete) return Future.value('https://signed.test/$path');
    final c = Completer<String>();
    pending.add(c);
    return c.future;
  }
}

Widget _host(PwaImageUrlResolver? resolver, {String reference = _kPath}) =>
    ProviderScope(
      overrides: [pwaImageUrlResolverProvider.overrideWithValue(resolver)],
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 180,
            child: PwaStoredImage(
              reference: reference,
              placeholderColor: const Color(0xFF201A14),
            ),
          ),
        ),
      ),
    );

/// The network image actually mounted, or null while the frame shows a
/// placeholder.
NetworkImage? _mountedNetworkImage(WidgetTester tester) {
  final images = tester.widgetList<Image>(find.byType(Image));
  for (final img in images) {
    final provider = img.image;
    if (provider is NetworkImage) return provider;
  }
  return null;
}

void main() {
  group('a Storage path becomes a signed network image', () {
    testWidgets('IMG01: the widget renders the URL the resolver minted', (
      tester,
    ) async {
      final signer = _Signer();
      final resolver = PwaImageUrlResolver(signer: signer.sign);

      await tester.pumpWidget(_host(resolver));
      // First frame: nothing signed yet, so a placeholder is correct.
      expect(_mountedNetworkImage(tester), isNull);

      await tester.pump(); // let the signature future settle
      expect(
        _mountedNetworkImage(tester)?.url,
        'https://signed.test/$_kPath',
        reason: 'the signed URL must reach an Image widget',
      );
      expect(signer.calls, [_kPath]);
    });

    testWidgets('IMG02: a bundle asset never asks for a signature', (
      tester,
    ) async {
      final signer = _Signer();
      final resolver = PwaImageUrlResolver(signer: signer.sign);

      await tester.pumpWidget(
        _host(resolver, reference: 'assets/showcase/living_after.jpg'),
      );
      await tester.pump();

      expect(signer.calls, isEmpty);
      expect(_mountedNetworkImage(tester), isNull);
      expect(find.byType(Image), findsOneWidget); // an Image.asset
    });

    testWidgets('IMG03: a Storage path with NO resolver shows nothing, '
        'never a fixture', (tester) async {
      await tester.pumpWidget(_host(null));
      await tester.pump();
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('IMG04: a signature that fails leaves the frame empty', (
      tester,
    ) async {
      final resolver = PwaImageUrlResolver(
        signer: (_, _) => Future.error(StateError('storage down')),
      );
      await tester.pumpWidget(_host(resolver));
      await tester.pump();
      expect(find.byType(Image), findsNothing);
    });
  });

  group('the resolver behaves under real timing', () {
    testWidgets('IMG10: a signature arriving AFTER the first build still '
        'reaches the screen', (tester) async {
      // The Architect builds its cards during a route transition, so the
      // signature almost always lands on a later frame than the first build.
      final signer = _Signer()..autoComplete = false;
      final resolver = PwaImageUrlResolver(signer: signer.sign);

      await tester.pumpWidget(_host(resolver));
      await tester.pump();
      expect(_mountedNetworkImage(tester), isNull, reason: 'still pending');

      signer.pending.single.complete('https://signed.test/late');
      await tester.pump();
      await tester.pump();

      expect(
        _mountedNetworkImage(tester)?.url,
        'https://signed.test/late',
        reason: 'a late signature must still be applied',
      );
    });

    testWidgets('IMG11: several widgets on the SAME path share one signature', (
      tester,
    ) async {
      // The Architect shows a card per vision, and the filmstrip repeats them.
      final signer = _Signer();
      final resolver = PwaImageUrlResolver(signer: signer.sign);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [pwaImageUrlResolverProvider.overrideWithValue(resolver)],
          child: MaterialApp(
            home: Scaffold(
              body: Column(
                children: List.generate(
                  3,
                  (i) => SizedBox(
                    width: 100,
                    height: 60,
                    child: PwaStoredImage(
                      key: ValueKey('card-$i'),
                      reference: _kPath,
                      placeholderColor: const Color(0xFF201A14),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        signer.calls.length,
        1,
        reason: 'three cards on one path must mint ONE url',
      );
      expect(tester.widgetList<Image>(find.byType(Image)), hasLength(3));
    });

    testWidgets('IMG12: DISTINCT visions each get their own image', (
      tester,
    ) async {
      // The regression that mattered: three visions, three different paths,
      // three different pictures. Never one image reused for all three.
      final signer = _Signer();
      final resolver = PwaImageUrlResolver(signer: signer.sign);
      const paths = [
        'users/u1/projects/p1/generated/v1.jpg',
        'users/u1/projects/p1/generated/v2.jpg',
        'users/u1/projects/p1/generated/v3.jpg',
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [pwaImageUrlResolverProvider.overrideWithValue(resolver)],
          child: MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  for (final p in paths)
                    SizedBox(
                      width: 100,
                      height: 60,
                      child: PwaStoredImage(
                        key: ValueKey('vision-card-$p'),
                        reference: p,
                        placeholderColor: const Color(0xFF201A14),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final urls = tester
          .widgetList<Image>(find.byType(Image))
          .map((i) => (i.image as NetworkImage).url)
          .toList();
      expect(urls, hasLength(3));
      expect(urls.toSet(), hasLength(3), reason: 'three distinct images');
      for (final p in paths) {
        expect(urls, contains('https://signed.test/$p'));
      }
    });

    testWidgets('IMG13: changing the reference re-signs and re-renders', (
      tester,
    ) async {
      final signer = _Signer();
      final resolver = PwaImageUrlResolver(signer: signer.sign);

      await tester.pumpWidget(_host(resolver));
      await tester.pump();
      expect(_mountedNetworkImage(tester)?.url, contains('v1.jpg'));

      await tester.pumpWidget(
        _host(resolver, reference: 'users/u1/projects/p1/generated/v9.jpg'),
      );
      await tester.pump();
      expect(_mountedNetworkImage(tester)?.url, contains('v9.jpg'));
      expect(signer.calls, hasLength(2));
    });
  });
}
