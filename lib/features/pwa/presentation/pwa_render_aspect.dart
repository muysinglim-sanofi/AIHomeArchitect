/// THE RENDER'S OWN SHAPE — measured, never assumed.
///
/// Reported from the phone (Round 3): a PORTRAIT room photo came back as a
/// LANDSCAPE result. The bucket says otherwise — that project's original is
/// 720×1280 and its generated vision is 1024×1536, both portrait, because the
/// engine picks its output size from the source (`_detect_output_size`:
/// w>h → 1536×1024, h>w → 1024×1536). What was landscape was the FRAME: the
/// result card and the Full Reveal wrapped every render in
/// `AspectRatio(3 / 2)` and painted it `BoxFit.cover`, which cropped the top
/// and bottom third off a portrait picture and showed the middle as if the
/// engine had widened the room.
///
/// iOS never assumes a shape. Its result card (`_GeneratedImageCard`) listens
/// to the decoded image and takes `width / height` from it; its Full Reveal
/// CONTAINs the picture inside a fixed-height block. This file is the web's
/// version of the first mechanism, made shareable: the decoded size of every
/// rendered image is recorded ONCE, keyed by its durable reference, and every
/// frame that shows it reads its aspect from here — with the 3:2 the engine
/// returns for a landscape photo as the value before the first decode.
///
/// It records; it does not decode twice. The listener is attached to the same
/// `ImageProvider` the `Image` widget resolves, so the bytes are decoded once
/// and the size is read off that decode.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What a landscape photo comes back as (1536×1024), and therefore the shape a
/// frame takes until its own render has been measured.
const double kPwaRenderAspect = 3 / 2;

/// Decoded `width / height` per image reference, for the session.
class PwaRenderAspects extends StateNotifier<Map<String, double>> {
  PwaRenderAspects() : super(const {});

  void record(String key, int width, int height) {
    if (key.isEmpty || width <= 0 || height <= 0) return;
    final aspect = width / height;
    if (state[key] == aspect) return;
    state = {...state, key: aspect};
  }
}

final pwaRenderAspectsProvider =
    StateNotifierProvider<PwaRenderAspects, Map<String, double>>(
  (ref) => PwaRenderAspects(),
);

/// The aspect to frame [key] at: its measured one; else [fallbackKey]'s, if
/// given and measured; else the engine's landscape.
///
/// The fallback exists for one moment: the render has just arrived and has
/// not been decoded yet, but the PHOTO it was made from has — it was on
/// screen in the working card. A child vision inherits the orientation of
/// the source it transforms (the engine sizes its output from the source's
/// bytes on every path), so the photo's shape is the render's shape, and the
/// frame lands right on the first frame instead of reflowing once the render
/// decodes. A restored project has no photo in memory and keeps 3:2 until
/// its render is measured.
double pwaAspectOf(Map<String, double> aspects, String key,
        {String? fallbackKey}) =>
    aspects[key] ??
    (fallbackKey == null ? null : aspects[fallbackKey]) ??
    kPwaRenderAspect;

/// Listen to [provider] until its first frame and record its size under [key].
///
/// Safe to call on every build: the provider's own cache means a second
/// resolve of the same image is a cache hit, and [PwaRenderAspects.record]
/// ignores a value it already holds.
void pwaRecordAspect(WidgetRef ref, ImageProvider provider, String key) {
  final stream = provider.resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      final width = info.image.width;
      final height = info.image.height;
      info.dispose();
      stream.removeListener(listener);
      // An image already in the cache completes SYNCHRONOUSLY, i.e. inside the
      // build that asked — and a provider may not be written during a build.
      // A microtask lands after the build scope closes and before the frame.
      Future<void>.microtask(() {
        try {
          ref.read(pwaRenderAspectsProvider.notifier).record(key, width, height);
        } catch (_) {
          // The widget that asked may be gone by the time the decode lands.
        }
      });
    },
    onError: (_, _) => stream.removeListener(listener),
  );
  stream.addListener(listener);
}

/// The Full Reveal's hero height: iOS's fixed image block ([blockH]) plus the
/// chrome band and the instruction line, bounded by what the rail and the
/// action slot leave ([available]).
///
/// The render's orientation plays no part here any more: the block is the
/// OUTER canvas and stays put; the render is CONTAINed inside it at its own
/// measured ratio over a blurred continuation of itself, exactly as iOS's
/// before/after screen does (`pwa_render_canvas.dart`).
double pwaRevealHeroHeight({
  required double blockH,
  required double available,
  required double chromeH,
  required double footH,
}) {
  final ceiling = available.clamp(160.0, double.infinity).toDouble();
  return (blockH + chromeH + footH).clamp(160.0, ceiling).toDouble();
}

/// `Image.memory` that also records its decoded size under [aspectKey].
class PwaMemoryImage extends ConsumerWidget {
  const PwaMemoryImage({
    super.key,
    required this.bytes,
    required this.aspectKey,
    this.fit = BoxFit.cover,
    this.errorBuilder,
  });

  final Uint8List bytes;
  final String aspectKey;
  final BoxFit fit;
  final ImageErrorWidgetBuilder? errorBuilder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = MemoryImage(bytes);
    pwaRecordAspect(ref, provider, aspectKey);
    return Image(image: provider, fit: fit, errorBuilder: errorBuilder);
  }
}

/// The key under which the photo being worked on is measured, before it has a
/// durable path of its own.
const String kPwaSourceAspectKey = 'pwa-source';
