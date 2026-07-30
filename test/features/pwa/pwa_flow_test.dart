// Batch 2 — PWA prototype widget + responsive tests. Deterministic (zero-delay
// mock via provider override), no real services, no real network.

import 'dart:typed_data';

import 'package:ai_home_architect/core/media/ayden_image_source.dart';
import 'package:ai_home_architect/features/pwa/application/pwa_controller.dart';
import 'package:ai_home_architect/features/pwa/application/pwa_entry.dart';
import 'package:ai_home_architect/features/pwa/application/pwa_layout.dart';
import 'package:ai_home_architect/features/pwa/data/mock_pwa_experience_repository.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_experience.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_widgets.dart';
import 'package:ai_home_architect/shared/widgets/reveal_hero.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

AydenImageSource _fakeSource() => AydenImageSource(
      bytes: Uint8List.fromList(const [1, 2, 3, 4]),
      filename: 'room.jpg',
    );

/// Build the PWA at [size], drive it to the architect phase deterministically,
/// and return the container so tests can assert on state.
Future<ProviderContainer> _pumpToArchitect(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final container = ProviderContainer(overrides: [
    pwaRepositoryProvider
        .overrideWithValue(MockPwaExperienceRepository(workDelay: Duration.zero)),
  ]);
  addTearDown(container.dispose);

  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(home: PwaExperience()),
  ));
  final controller = container.read(pwaControllerProvider.notifier);
  controller.setSource(_fakeSource()); // no room / atmosphere chosen
  await controller.generateFirstVision();
  await tester.pump(); // rebuild → architect
  await tester.pump(const Duration(seconds: 3)); // clear reveal auto-sweep timers
  return container;
}

void main() {
  group('Web entry decision', () {
    test('web → /pwa, mobile → /splash', () {
      expect(initialLocationForPlatform(true), kPwaRoutePath);
      expect(initialLocationForPlatform(false), kMobileInitialLocation);
    });
  });

  test('default PWA repository is the offline mock (no production service)', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(pwaRepositoryProvider), isA<MockPwaExperienceRepository>());
  });

  group('Responsive layout utility', () {
    test('breakpoints map width → form factor', () {
      expect(pwaFormFactorForWidth(390), PwaFormFactor.mobile);
      expect(pwaFormFactorForWidth(768), PwaFormFactor.tablet);
      expect(pwaFormFactorForWidth(1440), PwaFormFactor.desktop);
      expect(pwaIsTwoPane(PwaFormFactor.desktop), isTrue);
      expect(pwaIsTwoPane(PwaFormFactor.mobile), isFalse);
    });
  });

  testWidgets('Primary flow reaches architect with the reveal, no mandatory choice',
      (tester) async {
    final container = await _pumpToArchitect(tester, const Size(1440, 900));
    final state = container.read(pwaControllerProvider);
    expect(state.phase, PwaPhase.architect);
    expect(state.versions, hasLength(1));
    // The Full Reveal (RevealHero) is present, with the atmospheres directly below.
    expect(find.byType(RevealHero), findsWidgets);
    expect(find.byType(PwaAtmosphereStrip), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  group('Responsive smoke — no overflow', () {
    for (final size in const [
      Size(390, 844), // mobile
      Size(768, 1024), // tablet
      Size(1440, 900), // desktop
    ]) {
      testWidgets('renders architect at ${size.width.toInt()}x${size.height.toInt()}',
          (tester) async {
        await _pumpToArchitect(tester, size);
        expect(tester.takeException(), isNull);
      });
    }
  });

  testWidgets('Mobile version chip opens the near-full-screen versions sheet',
      (tester) async {
    final container = await _pumpToArchitect(tester, const Size(390, 844));
    // Header shows "1 vision"; tap it to open the sheet.
    final chip = find.text('1 vision');
    expect(chip, findsOneWidget);
    await tester.tap(chip);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Your visions'), findsOneWidget);
    expect(container.read(pwaControllerProvider).versions, hasLength(1));
    expect(tester.takeException(), isNull);
  });
}
