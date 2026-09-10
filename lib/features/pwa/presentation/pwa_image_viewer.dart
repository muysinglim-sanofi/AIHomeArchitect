/// FULLSCREEN — the render, as large as the screen allows, and explorable.
///
/// Why this is a route and not a dialog
/// ------------------------------------
/// Closing it must land the person back exactly where they were: the same
/// project, the same scroll position, the same vision selected. A pushed
/// opaque route does that for free — nothing underneath is rebuilt or
/// disposed — and it also gives the browser Back button the meaning a person
/// expects on a photo: leave the photo, not the project.
///
/// What it does NOT do
/// -------------------
/// It does not navigate to the Full Reveal, which is a different thing: the
/// Reveal is the before/after presentation with its atmosphere rail. This is
/// the picture, alone, with room to look at it.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/pwa_controller.dart' show pwaImageUrlResolverProvider;
import '../data/pwa_image_export.dart';
import '../l10n/pwa_l10n.dart';
import 'pwa_stored_image.dart';
import 'pwa_theme.dart';
import 'pwa_type.dart';

/// How a vision leaves Ayden. Overridden in `main_pwa.dart` with the real
/// browser implementation; unsupported everywhere else, which is the honest
/// default for a test and for the offline mock.
final pwaImageExporterProvider = Provider<PwaImageExporter>(
  (ref) => const PwaUnsupportedImageExporter(),
);

/// Open [reference] fullscreen. Returns when the viewer is closed.
Future<void> showPwaImageViewer(
  BuildContext context, {
  required String reference,
  required String title,
  required String fileName,
}) {
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: true,
      barrierColor: Colors.black,
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, _, _) => _PwaImageViewer(
        reference: reference,
        title: title,
        fileName: fileName,
      ),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}

class _PwaImageViewer extends ConsumerStatefulWidget {
  const _PwaImageViewer({
    required this.reference,
    required this.title,
    required this.fileName,
  });

  final String reference;
  final String title;
  final String fileName;

  @override
  ConsumerState<_PwaImageViewer> createState() => _PwaImageViewerState();
}

class _PwaImageViewerState extends ConsumerState<_PwaImageViewer> {
  /// True while a share or a save is in flight, so neither can be started
  /// twice and the buttons can say they are working.
  bool _busy = false;

  /// Set once the picture's URL is known — the same signed URL the `<img>`
  /// uses, so the file that leaves is the one on screen and it is fetched
  /// from cache rather than generated a second time.
  String? _url;

  @override
  void initState() {
    super.initState();
    // The viewer is a black surface: the status bar has to be light on it.
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
    _resolve();
  }

  Future<void> _resolve() async {
    try {
      final resolver = ref.read(pwaImageUrlResolverProvider);
      // Null in the offline mock, where a bundle asset is already its own URL.
      final url = resolver == null
          ? widget.reference
          : await resolver.resolve(widget.reference);
      if (mounted) setState(() => _url = url);
      // WARM THE BYTES NOW. `navigator.share` is gated on transient user
      // activation, so fetching a multi-megabyte render inside the tap spends
      // the activation and the sheet never opens — measured on preprod as
      // `NotAllowedError - Must be handling a user gesture`. Doing it here
      // costs nothing the person waits for: the same URL is what the picture
      // on screen is already loading.
      if (url.isNotEmpty) {
        await ref
            .read(pwaImageExporterProvider)
            .prefetch(url: url, fileName: widget.fileName);
      }
    } catch (_) {
      // The picture will still render through PwaStoredImage, which signs on
      // its own; only the export controls stay disabled.
    }
  }

  Future<void> _run(
      Future<PwaExportOutcome> Function(PwaImageExporter e, String url) op) async {
    final url = _url;
    if (_busy || url == null || url.isEmpty) return;
    setState(() => _busy = true);
    final outcome = await op(ref.read(pwaImageExporterProvider), url);
    if (!mounted) return;
    setState(() => _busy = false);
    final l = context.pwaL10n;
    // Silence is right for the two outcomes the person can see for
    // themselves: the sheet opened, or they closed it.
    final message = switch (outcome) {
      PwaExportOutcome.done => null,
      PwaExportOutcome.cancelled => null,
      PwaExportOutcome.unsupported => l.shareUnavailable,
      PwaExportOutcome.failed => l.errUnknown,
    };
    if (message == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: pwaSans(fontSize: 13, color: pwaOnDark)),
        backgroundColor: pwaCharcoal,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.pwaL10n;
    final ready = (_url ?? '').isNotEmpty;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // THE PICTURE. `InteractiveViewer` gives pinch, double-drag pan
            // and trackpad zoom from the framework — no gesture code of our
            // own, and no page scroll behind it, because the route is opaque
            // and full-screen.
            Positioned.fill(
              child: InteractiveViewer(
                key: const ValueKey('pwa-viewer-interactive'),
                minScale: 1,
                maxScale: 5,
                child: Center(
                  child: PwaStoredImage(
                    key: ValueKey('pwa-viewer-${widget.reference}'),
                    reference: widget.reference,
                    placeholderColor: Colors.black,
                    // CONTAIN, always: a fullscreen viewer that cropped would
                    // be hiding the part of the room the person opened it to
                    // see.
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),

            // ── top: what this is, and the way out ──────────────────────────
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(8, 8, 12, 16),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xCC000000), Color(0x00000000)],
                  ),
                ),
                child: Row(
                  children: [
                    IconButton(
                      key: const ValueKey('pwa-viewer-close'),
                      tooltip: MaterialLocalizations.of(context)
                          .closeButtonTooltip,
                      icon: const Icon(Icons.close_rounded, color: Colors.white),
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                    Expanded(
                      child: Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: PwaType.bodyMuted(color: Colors.white70),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── bottom: take it with you ────────────────────────────────────
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Color(0xCC000000), Color(0x00000000)],
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _ViewerAction(
                      key: const ValueKey('pwa-viewer-share'),
                      icon: Icons.ios_share_rounded,
                      label: l.shareVision,
                      enabled: ready && !_busy,
                      onTap: () => _run((e, url) => e.share(
                            url: url,
                            fileName: widget.fileName,
                            title: widget.title,
                          )),
                    ),
                    const SizedBox(width: 12),
                    _ViewerAction(
                      key: const ValueKey('pwa-viewer-save'),
                      icon: Icons.download_rounded,
                      label: l.saveImage,
                      enabled: ready && !_busy,
                      onTap: () => _run((e, url) => e.save(
                            url: url,
                            fileName: widget.fileName,
                          )),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One action on the black ground: a glyph, a word, and enough contrast to sit
/// on a photograph of any brightness.
class _ViewerAction extends StatelessWidget {
  const _ViewerAction({
    super.key,
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = enabled ? Colors.white : Colors.white38;
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: enabled ? const Color(0x33FFFFFF) : const Color(0x14FFFFFF),
        borderRadius: BorderRadius.circular(PwaGap.radiusPill),
        child: InkWell(
          borderRadius: BorderRadius.circular(PwaGap.radiusPill),
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 19, color: fg),
                const SizedBox(width: 9),
                Text(label,
                    style: pwaSans(
                        fontSize: 14, fontWeight: FontWeight.w600, color: fg)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
