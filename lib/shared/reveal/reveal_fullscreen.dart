/// AYDEN Part A — Reveal engine (A4): immersive fullscreen reveal.
///
/// A dedicated, edge-to-edge premium experience (option A): the cinematic
/// reveal on an ambient [RevealCanvas] backdrop, with its OWN controller
/// (cinematic profile), surface scrub, release-snap, settle haptic, Replay and
/// close. Plays once → settles on AFTER (no loop) so the user inhabits the
/// image. Frontend-only; reuses RevealCanvas read-only.
library;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemChrome, SystemUiMode;

import '../../core/constants/app_colors.dart';
import '../widgets/reveal_canvas.dart';
import 'reveal_controller.dart';
import 'reveal_profile.dart';
import 'reveal_widget.dart';

class RevealFullscreenScreen extends StatefulWidget {
  final String? beforeUrl;
  final String? afterUrl;

  const RevealFullscreenScreen({super.key, this.beforeUrl, this.afterUrl});

  @override
  State<RevealFullscreenScreen> createState() => _RevealFullscreenScreenState();
}

class _RevealFullscreenScreenState extends State<RevealFullscreenScreen>
    with TickerProviderStateMixin {
  late final RevealController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        RevealController(vsync: this, profile: RevealProfile.cinematic);
    // True immersive — hide system chrome while in the fullscreen reveal.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _controller.dispose();
    super.dispose();
  }

  ImageProvider? _provider(String? url) {
    if (url == null || url.isEmpty) return null;
    return url.startsWith('assets/')
        ? AssetImage(url)
        : CachedNetworkImageProvider(url);
  }

  Widget _image(String? url) {
    if (url == null || url.isEmpty) {
      return const ColoredBox(color: AppColors.shimmerBase);
    }
    if (url.startsWith('assets/')) {
      return Image.asset(url,
          fit: BoxFit.contain,
          width: double.infinity,
          height: double.infinity,
          errorBuilder: (_, _, _) =>
              const ColoredBox(color: AppColors.shimmerBase));
    }
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.contain,
      width: double.infinity,
      height: double.infinity,
      placeholder: (_, _) => const ColoredBox(color: AppColors.shimmerBase),
      errorWidget: (_, _, _) => const ColoredBox(color: AppColors.shimmerBase),
    );
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top + 8;
    return Scaffold(
      backgroundColor: AppColors.textPrimary,
      body: Stack(
        fit: StackFit.expand,
        children: [
          RevealCanvas(
            ambientImage: _provider(widget.afterUrl),
            child: RevealWidget(
              afterImage: _image(widget.afterUrl),
              beforeImage:
                  widget.beforeUrl == null ? null : _image(widget.beforeUrl),
              controller: _controller,
              interaction: RevealInteraction.surface,
              showLabels: false,
            ),
          ),
          // Close (top-left) — also exits via system back.
          Positioned(
            top: top,
            left: 12,
            child: _CircleButton(
              icon: Icons.close,
              onTap: () => Navigator.of(context).maybePop(),
            ),
          ),
          // Replay (top-right) — re-trigger the reveal in place.
          Positioned(
            top: top,
            right: 12,
            child: _CircleButton(
              icon: Icons.replay,
              onTap: _controller.replay,
            ),
          ),
        ],
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.65),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 16, color: AppColors.textPrimary),
        ),
      ),
    );
  }
}
