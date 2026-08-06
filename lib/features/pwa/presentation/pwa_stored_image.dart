/// The ONE way a vision image reaches the screen.
///
/// A generated vision lives in a PRIVATE bucket, so it has no URL that can be
/// put in an `<img>` — it has a PATH, and a URL has to be minted for it and
/// re-minted when that signature expires. Every place that shows a vision goes
/// through this widget so that logic exists once: the Architect card, the
/// filmstrip, the versions sheet, the reveal, the project covers.
///
/// Two rules it enforces:
///   • a bundle asset (`assets/...`) renders as an asset, unchanged — that is
///     still correct for the Hero, the atmosphere previews and the offline mock;
///   • a Storage path NEVER falls back to a bundle asset. If the URL cannot be
///     minted or the image cannot be fetched, the frame stays empty. Substituting
///     a fixture would show the user a room that is not theirs.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/pwa_controller.dart';
import '../data/pwa_image_url_resolver.dart';

class PwaStoredImage extends ConsumerStatefulWidget {
  const PwaStoredImage({
    super.key,
    required this.reference,
    required this.placeholderColor,
    this.fit = BoxFit.cover,
  });

  /// A durable Storage path, or a bundle asset path.
  final String reference;

  /// Shown while resolving and when the image cannot be rendered. Passed in so
  /// each surface keeps its own calm background instead of a shared grey.
  final Color placeholderColor;

  final BoxFit fit;

  @override
  ConsumerState<PwaStoredImage> createState() => _PwaStoredImageState();
}

class _PwaStoredImageState extends ConsumerState<PwaStoredImage> {
  String? _url;
  bool _failed = false;

  /// One re-signature per reference. An expired signature deserves a retry; a
  /// genuinely missing object does not deserve an infinite loop.
  bool _resigned = false;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant PwaStoredImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reference != widget.reference) {
      _url = null;
      _failed = false;
      _resigned = false;
      _resolve();
    }
  }

  Future<void> _resolve() async {
    final reference = widget.reference;
    if (!pwaIsStoragePath(reference)) return; // bundle asset — nothing to sign
    final resolver = ref.read(pwaImageUrlResolverProvider);
    if (resolver == null) {
      // A Storage path with no way to sign it means this build was wired
      // wrongly. Show nothing rather than something that isn't the user's room.
      if (mounted) setState(() => _failed = true);
      return;
    }
    try {
      final url = await resolver.resolve(reference);
      // The reference can change while a signature is in flight (the filmstrip
      // recycles these): drop a result that no longer belongs to this widget.
      if (!mounted || widget.reference != reference) return;
      setState(() {
        _url = url;
        _failed = false;
      });
    } catch (_) {
      if (!mounted || widget.reference != reference) return;
      setState(() => _failed = true);
    }
  }

  /// The usual cause of a load failure is an expired signature, and the fix is a
  /// new URL from the same durable path. Never a fixture.
  void _resignOnce() {
    if (_resigned) return;
    _resigned = true;
    ref.read(pwaImageUrlResolverProvider)?.invalidate(widget.reference);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _url = null);
      _resolve();
    });
  }

  Widget get _placeholder => ColoredBox(color: widget.placeholderColor);

  @override
  Widget build(BuildContext context) {
    if (!pwaIsStoragePath(widget.reference)) {
      return Image.asset(
        widget.reference,
        fit: widget.fit,
        errorBuilder: (_, _, _) => _placeholder,
      );
    }
    final url = _url;
    if (_failed || url == null) return _placeholder;
    return Image.network(
      url,
      fit: widget.fit,
      errorBuilder: (_, _, _) {
        _resignOnce();
        return _placeholder;
      },
      loadingBuilder: (context, child, progress) =>
          progress == null ? child : _placeholder,
    );
  }
}
