/// AYDEN card system — data catalog (rooms split Indoor/Outdoor, atmospheres
/// with editorial subtitles). Plain data; no logic, no l10n dependency (the
/// preview uses these labels directly). Assets sliced into assets/cards/.
library;

class RoomCardData {
  final String id;
  final String label;
  final String asset;
  const RoomCardData(this.id, this.label, this.asset);
}

class AtmosphereCardData {
  final String id;
  final String name;
  final String subtitle;
  final String asset;
  const AtmosphereCardData(this.id, this.name, this.subtitle, this.asset);
}

/// MVP rooms hierarchy (Featured + Library). HERO = the 6 most requested /
/// highest-conversion spaces (large grid). MORE = the rest (secondary row).
///
/// `id` = the CANONICAL camelCase id (matches `RoomTypeImages.interiorIds` /
/// `exteriorIds` + backend free-tier ids). `label` = the English visual label
/// (display only; routing/free-tier use the localized label via
/// `RoomTypeImages.labelForId`). `asset` = the sliced snake_case image.
const kHeroRooms = <RoomCardData>[
  RoomCardData('livingRoom', 'Living Room', 'assets/cards/rooms/living_room.png'),
  RoomCardData('masterBedroom', 'Bedroom', 'assets/cards/rooms/master_bedroom.png'),
  RoomCardData('kitchen', 'Kitchen', 'assets/cards/rooms/kitchen.png'),
  RoomCardData('bathroom', 'Bathroom', 'assets/cards/rooms/bathroom.png'),
  RoomCardData('terrace', 'Terrace', 'assets/cards/rooms/terrace.png'),
];

const kMoreRooms = <RoomCardData>[
  RoomCardData('diningRoom', 'Dining Room', 'assets/cards/rooms/dining_room.png'),
  RoomCardData('homeOffice', 'Home Office', 'assets/cards/rooms/home_office.png'),
  RoomCardData('balcony', 'Balcony', 'assets/cards/rooms/balcony.png'),
  RoomCardData('entranceHall', 'Entrance Hall', 'assets/cards/rooms/entrance_hall.png'),
  RoomCardData('poolArea', 'Pool Area', 'assets/cards/rooms/pool_area.png'),
  RoomCardData('garden', 'Garden', 'assets/cards/rooms/garden.png'),
  RoomCardData('houseFacade', 'House Facade', 'assets/cards/rooms/house_facade.png'),
  RoomCardData('driveway', 'Driveway', 'assets/cards/rooms/driveway.png'),
];

/// Ordered by popularity (preview).
const kAtmosphereCards = <AtmosphereCardData>[
  AtmosphereCardData('warm_modern', 'Warm Modern',
      'Inspired by boutique sunset villas', 'assets/cards/atmospheres/warm_modern.png'),
  AtmosphereCardData('japandi_calm', 'Japandi Calm',
      'Inspired by serene Kyoto retreats', 'assets/cards/atmospheres/japandi_calm.png'),
  AtmosphereCardData('soft_luxury', 'Soft Luxury',
      'Inspired by 5-star boutique hotels', 'assets/cards/atmospheres/soft_luxury.png'),
  AtmosphereCardData('nordic_warmth', 'Nordic Warmth',
      'Inspired by Scandinavian winter escapes', 'assets/cards/atmospheres/nordic_warmth.png'),
  AtmosphereCardData('tropical_escape', 'Tropical Escape',
      'Inspired by Bali luxury resorts', 'assets/cards/atmospheres/tropical_escape.png'),
];

/// id → card visual data (subtitle + asset). Lets the real flow iterate the
/// canonical ordered atmosphere list (AppLocalizations.atmospheres) for
/// identity/free-tier while pulling the new visuals by id.
final Map<String, AtmosphereCardData> kAtmosphereCardById = {
  for (final a in kAtmosphereCards) a.id: a,
};
