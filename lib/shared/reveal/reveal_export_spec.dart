/// AYDEN Part A — Reveal engine (A1, pure logic).
///
/// Serializable description of a reveal export request. Declared NOW (per the
/// architecture's Challenge B) so the future server-side ffmpeg renderer is a
/// **pure consumer** of the same timeline — never a second, divergent system.
///
/// NOTHING consumes this in A1. No backend route, no rendering. It only proves
/// the timeline is fully serializable and round-trips losslessly.
library;

import 'reveal_profile.dart';

class RevealExportSpec {
  final String beforeUrl;
  final String afterUrl;

  /// The full timeline contract sent to the renderer (the parity source).
  final RevealProfile profile;

  /// Output aspect ratio (width / height), e.g. 9/16 for Reels.
  final double aspect;

  /// Apply the subtle AYDEN watermark (premium export = false).
  final bool watermark;

  const RevealExportSpec({
    required this.beforeUrl,
    required this.afterUrl,
    required this.profile,
    required this.aspect,
    this.watermark = true,
  });

  Map<String, dynamic> toJson() => {
        'beforeUrl': beforeUrl,
        'afterUrl': afterUrl,
        'aspect': aspect,
        'watermark': watermark,
        'profile': profile.toJson(),
      };

  factory RevealExportSpec.fromJson(Map<String, dynamic> json) =>
      RevealExportSpec(
        beforeUrl: json['beforeUrl'] as String,
        afterUrl: json['afterUrl'] as String,
        aspect: (json['aspect'] as num).toDouble(),
        watermark: json['watermark'] as bool,
        profile: RevealProfile.fromJson(json['profile'] as Map<String, dynamic>),
      );
}
