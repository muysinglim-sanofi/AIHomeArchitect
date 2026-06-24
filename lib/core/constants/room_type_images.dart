import 'package:flutter/widgets.dart';
import '../l10n/app_localizations.dart';

/// Wave 4.10h — Centralized, curated room-type imagery.
///
/// ONE source of truth so the room-type selection reads as a *coherent
/// architectural set* (calm, wide, neutral-graded framing — "choose what
/// kind of architecture we are transforming"), never random inline Unsplash
/// scattered across screens.
///
/// Keyed by a STABLE canonical id (the existing l10n room key), resolved to
/// the live localized label at call time via the public per-room
/// `AppLocalizations` getters. This means:
///   • the map is correct in every locale (en / km / …) — we never key on a
///     hard-coded English string,
///   • the value that flows through routing / session / generation is the
///     SAME localized label as before (non-regression — this layer only
///     decides which picture to show, never the selection value),
///   • adding a room later = one entry here (future scalability).
///
/// Curated stock URLs are explicitly allowed for now (no bespoke assets yet).
/// They are pinned photo IDs with sized params (cheap, stable decode). If a
/// URL ever fails, `RoomTypeCard` shows a calm typographic fallback in the
/// same shell — never a broken box.
class RoomTypeImages {
  RoomTypeImages._();

  /// Canonical room order (matches `AppLocalizations.interiorRooms` then
  /// `exteriorRooms`). Used only for stable keying — not user-facing.
  static const interiorIds = <String>[
    'livingRoom',
    'masterBedroom',
    'kitchen',
    'bathroom',
    'homeOffice',
    'diningRoom',
    'entranceHall',
  ];
  static const exteriorIds = <String>[
    'houseFacade',
    'garden',
    'poolArea',
    'terrace',
    'balcony',
    'driveway',
  ];

  // Coherent architect-grade set — calm, wide architectural framing, neutral
  // grading, all the same visual language (interior spaces / exterior
  // architecture). Pinned IDs + sized params.
  static const _byId = <String, String>{
    'livingRoom':
        'https://images.unsplash.com/photo-1505691938895-1758d7feb511?w=640&q=70&auto=format&fit=crop',
    'masterBedroom':
        'https://images.unsplash.com/photo-1505693416388-ac5ce068fe85?w=640&q=70&auto=format&fit=crop',
    'kitchen':
        'https://images.unsplash.com/photo-1556909114-f6e7ad7d3136?w=640&q=70&auto=format&fit=crop',
    'bathroom':
        'https://images.unsplash.com/photo-1620626011761-996317b8d101?w=640&q=70&auto=format&fit=crop',
    'homeOffice':
        'https://images.unsplash.com/photo-1593476550610-87baa860004a?w=640&q=70&auto=format&fit=crop',
    'diningRoom':
        'https://images.unsplash.com/photo-1617806118233-18e1de247200?w=640&q=70&auto=format&fit=crop',
    'entranceHall':
        'https://images.unsplash.com/photo-1600494603989-9650cf6dad51?w=640&q=70&auto=format&fit=crop',
    'houseFacade':
        'https://images.unsplash.com/photo-1600585154340-be6161a56a0c?w=640&q=70&auto=format&fit=crop',
    'garden':
        'https://images.unsplash.com/photo-1558904541-efa843a96f01?w=640&q=70&auto=format&fit=crop',
    'poolArea':
        'https://images.unsplash.com/photo-1572331165267-854da2b10ccc?w=640&q=70&auto=format&fit=crop',
    'terrace':
        'https://images.unsplash.com/photo-1600566752355-35792bedcfea?w=640&q=70&auto=format&fit=crop',
    'balcony':
        'https://images.unsplash.com/photo-1600607687939-ce8a6c25118c?w=640&q=70&auto=format&fit=crop',
    'driveway':
        'https://images.unsplash.com/photo-1600585154526-990dced4db0d?w=640&q=70&auto=format&fit=crop',
  };

  /// id → localized label, via the existing public per-room l10n getters
  /// (stable keying, locale-correct). Keeping this list here (rather than in
  /// l10n) avoids touching `app_localizations.dart` (out of scope) while
  /// staying centralized.
  static final Map<String, String Function(AppLocalizations)> _labelOf = {
    'livingRoom': (l) => l.livingRoom,
    'masterBedroom': (l) => l.masterBedroom,
    'kitchen': (l) => l.kitchen,
    'bathroom': (l) => l.bathroom,
    'homeOffice': (l) => l.homeOffice,
    'diningRoom': (l) => l.diningRoom,
    'entranceHall': (l) => l.entranceHall,
    'houseFacade': (l) => l.houseFacade,
    'garden': (l) => l.garden,
    'poolArea': (l) => l.poolArea,
    'terrace': (l) => l.terrace,
    'balcony': (l) => l.balcony,
    'driveway': (l) => l.driveway,
  };

  /// #4 — backend / Ayden-Decide room ids are snake_case or short forms
  /// ("living_room", "bedroom", "office") while [_labelOf] keys are camelCase.
  /// This bridges them so a room returned by the backend resolves to a proper
  /// (localized) label instead of leaking the raw id into the UI / titles.
  static const Map<String, String> _backendIdAlias = {
    'living_room': 'livingRoom',
    'bedroom': 'masterBedroom',
    'master_bedroom': 'masterBedroom',
    'kitchen': 'kitchen',
    'bathroom': 'bathroom',
    'office': 'homeOffice',
    'home_office': 'homeOffice',
    'dining_room': 'diningRoom',
    'entrance': 'entranceHall',
    'entrance_hall': 'entranceHall',
    'hallway': 'entranceHall',
    'facade': 'houseFacade',
    'house_facade': 'houseFacade',
    'garden': 'garden',
    'pool': 'poolArea',
    'pool_area': 'poolArea',
    'terrace': 'terrace',
    'balcony': 'balcony',
    'driveway': 'driveway',
  };

  /// Resolve ANY room id form → canonical camelCase id (a [_labelOf] key), or
  /// null. A camelCase id passes through; a snake_case/short backend id maps via
  /// [_backendIdAlias]. The label helpers call this so a raw snake id never
  /// reaches the UI (routing/free-tier behaviour is unchanged — they still emit
  /// the same canonical English value / camelCase id as before).
  static String? _canonicalId(String raw) {
    final r = raw.trim();
    if (r.isEmpty) return null;
    if (_labelOf.containsKey(r)) return r;
    return _backendIdAlias[r.toLowerCase()];
  }

  /// Canonical id → LOCALIZED room label (the routing/free-tier value the
  /// screens pass around). Lets the new card system key by stable camelCase
  /// id while still routing the localized label the backend expects.
  static String? labelForId(AppLocalizations l10n, String id) {
    final cid = _canonicalId(id);
    return cid == null ? null : _labelOf[cid]!(l10n);
  }

  /// Locale-stable ENGLISH label for an id. THIS is the canonical value routed
  /// through session/generation as `room_type` — the backend prompt engine's
  /// DNA room lookup keys off English room names ("Living Room", "Kitchen", …).
  /// Routing the localized label instead (e.g. "Salon") makes the backend drop
  /// the whole room DNA block (room context, TV anchor, furniture directives).
  /// UI display may still localize via [labelForId]; the VALUE must stay English.
  static final AppLocalizations _enL10n = AppLocalizations(const Locale('en'));
  static String? enLabelForId(String id) {
    final cid = _canonicalId(id);
    return cid == null ? null : _labelOf[cid]!(_enL10n);
  }

  /// Localized DISPLAY label for a routed (canonical English) room value.
  /// Round-trips English value → id → localized label so the UI can show
  /// "Salon" while the VALUE stays the backend-safe "Living Room". Falls back
  /// to the value itself for unknown/legacy strings.
  static String displayLabel(AppLocalizations l10n, String value) {
    final id = idForLabel(l10n, value);
    if (id == null) return value;
    return labelForId(l10n, id) ?? value;
  }

  /// Curated image URL for a LOCALIZED room label (the value the screens
  /// already pass around). Null ⇒ the caller shows the calm fallback.
  static String? urlForLabel(AppLocalizations l10n, String label) {
    for (final entry in _labelOf.entries) {
      // Match the canonical English value (what we route) OR the current-locale
      // label (legacy/persisted values) — locale-stable.
      if (entry.value(_enL10n) == label || entry.value(l10n) == label) {
        return _byId[entry.key];
      }
    }
    return null;
  }

  /// Wave 5.17d — canonical id (locale-stable) for a LOCALIZED room
  /// label. Used to populate the `room_type_id` form param on /generate,
  /// which drives the free-tier scope check server-side. Returns null
  /// when the label doesn't match any known room (free user → backend
  /// will reject with 402 FREE_TIER_RESTRICTED, which is the correct
  /// behaviour for an out-of-catalogue label).
  static String? idForLabel(AppLocalizations l10n, String label) {
    if (label.isEmpty) return null;
    for (final entry in _labelOf.entries) {
      // Match the canonical English value (what we route) OR the current-locale
      // label (legacy/persisted values) — locale-stable.
      if (entry.value(_enL10n) == label || entry.value(l10n) == label) {
        return entry.key;
      }
    }
    // #4 — last resort: a snake_case/short backend id ("living_room"). Resolve
    // it so displayLabel() works on a raw backend room instead of echoing it.
    return _canonicalId(label);
  }
}
