import 'package:flutter/material.dart';

// Single source of truth for all atmosphere metadata.
// Used by: AtmosphereCard, upload screen, before/after reveal, chat design
// direction modal, and FTUE onboarding screen 3.
//
// TWO SEPARATE IMAGE SYSTEMS:
//
//   Card hero  (heroImagePath → showcaseAsset → fallbackImageUrl)
//   Used by AtmosphereCard in upload/reveal/chat — shows the atmosphere style.
//
//   FTUE hero  (ftueHeroImagePath → showcaseAsset → fallbackImageUrl)
//   Used ONLY by FTUE Screen 3 large hero area — must show SAME baseline space
//   in multiple atmosphere transformations. Preserves architecture; changes style.

class AtmosphereStyle {
  final String id;
  final String name;
  final String tagline;

  // ── Card hero ─────────────────────────────────────────────────────────────────
  // Local asset (assets/atmospheres/{id}.jpg). Drop file to activate.
  final String heroImagePath;

  // Floating icon PNG (assets/atmospheres/{id}_icon.png). Drop file to activate.
  final String iconImagePath;

  // Reliable local fallback used when heroImagePath asset is absent.
  // Available only for atmospheres that have a real AI showcase output.
  // null → falls directly through to fallbackImageUrl.
  final String? showcaseAsset;

  // Network fallback (Unsplash) when both local assets are absent.
  final String fallbackImageUrl;

  // Material icon shown while iconImagePath asset is absent.
  final IconData iconData;

  // ── FTUE hero ─────────────────────────────────────────────────────────────────
  // Dedicated FTUE hero (assets/atmospheres/ftue/ftue_{id}.jpg).
  // Must show the SAME baseline architecture transformed into this atmosphere.
  // Drop file to activate — falls back to showcaseAsset then fallbackImageUrl.
  final String ftueHeroImagePath;

  const AtmosphereStyle({
    required this.id,
    required this.name,
    required this.tagline,
    required this.heroImagePath,
    required this.iconImagePath,
    this.showcaseAsset,
    required this.fallbackImageUrl,
    required this.iconData,
    required this.ftueHeroImagePath,
  });
}

const kAtmospheres = <AtmosphereStyle>[
  AtmosphereStyle(
    id: 'tropical_escape',
    name: 'Tropical Escape',
    tagline: 'Lush resort warmth with natural textures',
    heroImagePath: 'assets/atmospheres/tropical_escape.jpg',
    iconImagePath: 'assets/atmospheres/tropical_escape_icon.png',
    showcaseAsset: null,
    fallbackImageUrl:
        'https://images.unsplash.com/photo-1540541338537-41369ba26fa7?w=400&fit=crop&crop=center',
    iconData: Icons.beach_access,
    ftueHeroImagePath: 'assets/atmospheres/ftue/ftue_tropical_escape.jpg',
  ),
  AtmosphereStyle(
    id: 'warm_modern',
    name: 'Warm Modern',
    tagline: 'Contemporary comfort with inviting warmth',
    heroImagePath: 'assets/atmospheres/warm_modern.jpg',
    iconImagePath: 'assets/atmospheres/warm_modern_icon.png',
    showcaseAsset: 'assets/showcase/apartment_after.jpg',
    fallbackImageUrl:
        'https://images.unsplash.com/photo-1616594039964-ae0021a8b8bf?w=400&fit=crop&crop=center',
    iconData: Icons.wb_sunny_outlined,
    ftueHeroImagePath: 'assets/atmospheres/ftue/ftue_warm_modern.jpg',
  ),
  AtmosphereStyle(
    id: 'japandi_calm',
    name: 'Japandi Calm',
    tagline: 'Japanese-Scandinavian harmony and restraint',
    heroImagePath: 'assets/atmospheres/japandi_calm.jpg',
    iconImagePath: 'assets/atmospheres/japandi_calm_icon.png',
    showcaseAsset: 'assets/showcase/smallspace_after.jpg',
    fallbackImageUrl:
        'https://images.unsplash.com/photo-1583847268964-b28dc8f51f92?w=400&fit=crop&crop=center',
    iconData: Icons.horizontal_rule,
    ftueHeroImagePath: 'assets/atmospheres/ftue/ftue_japandi_calm.jpg',
  ),
  AtmosphereStyle(
    id: 'soft_luxury',
    name: 'Soft Luxury',
    tagline: 'Elegant materials and refined evening light',
    heroImagePath: 'assets/atmospheres/soft_luxury.jpg',
    iconImagePath: 'assets/atmospheres/soft_luxury_icon.png',
    showcaseAsset: 'assets/showcase/facade_after.jpg',
    fallbackImageUrl:
        'https://images.unsplash.com/photo-1616486338812-3dadae4b4ace?w=400&fit=crop&crop=center',
    iconData: Icons.star_border,
    ftueHeroImagePath: 'assets/atmospheres/ftue/ftue_soft_luxury.jpg',
  ),
  AtmosphereStyle(
    id: 'nordic_warmth',
    name: 'Nordic Warmth',
    tagline: 'Cozy Scandinavian tones and natural light',
    heroImagePath: 'assets/atmospheres/nordic_warmth.jpg',
    iconImagePath: 'assets/atmospheres/nordic_warmth_icon.png',
    showcaseAsset: null,
    fallbackImageUrl:
        'https://images.unsplash.com/photo-1501876725168-00c445821c9e?w=400&fit=crop&crop=center',
    iconData: Icons.ac_unit,
    ftueHeroImagePath: 'assets/atmospheres/ftue/ftue_nordic_warmth.jpg',
  ),
  AtmosphereStyle(
    id: 'nature_retreat',
    name: 'Nature Retreat',
    tagline: 'Biophilic design immersed in greenery',
    heroImagePath: 'assets/atmospheres/nature_retreat.jpg',
    iconImagePath: 'assets/atmospheres/nature_retreat_icon.png',
    showcaseAsset: null,
    fallbackImageUrl:
        'https://images.unsplash.com/photo-1518780664697-55e3ad937233?w=400&fit=crop&crop=center',
    iconData: Icons.eco,
    ftueHeroImagePath: 'assets/atmospheres/ftue/ftue_nature_retreat.jpg',
  ),
  AtmosphereStyle(
    id: 'desert_luxe',
    name: 'Desert Luxe',
    tagline: 'Warm earth tones with artisanal warmth',
    heroImagePath: 'assets/atmospheres/desert_luxe.jpg',
    iconImagePath: 'assets/atmospheres/desert_luxe_icon.png',
    showcaseAsset: null,
    fallbackImageUrl:
        'https://images.unsplash.com/photo-1566073771259-6a8506099945?w=400&fit=crop&crop=center',
    iconData: Icons.wb_twilight,
    ftueHeroImagePath: 'assets/atmospheres/ftue/ftue_desert_luxe.jpg',
  ),
];

/// Wave 5.17d — canonical atmosphere id from a possibly-decorated label
/// like "Nordic Warmth" or "Nordic Warmth · Vision 1". Used to populate
/// the `atmosphere_id` form param on /generate which drives the free-
/// tier scope check server-side. Returns null when the label doesn't
/// match any known atmosphere (free user → backend rejects with 402).
String? atmosphereIdFromLabel(String? label) {
  if (label == null || label.isEmpty) return null;
  final base = label.split('·').first.trim().toLowerCase();
  for (final a in kAtmospheres) {
    if (a.name.toLowerCase() == base) return a.id;
  }
  return null;
}
