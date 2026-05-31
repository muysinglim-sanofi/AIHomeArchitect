import '../models/project_model.dart';
import '../models/message_model.dart';

// ── Project 1 messages: Living Room Sanctuary ─────────────────────────────────
// Spans 3 days → produces "May 9" / "Yesterday" / "Today" separators in chat

final _p1Messages = [
  // May 9 (2 days ago)
  MessageModel(
    id: 'p1_1',
    content: 'Good bones — there\'s strong natural light near the seating area, which is genuinely valuable. I\'d warm up the materials significantly, layer the lighting properly, and refine the spatial flow. Are you leaning toward cozy luxury, Japandi restraint, or something more tropical and alive?',
    isAi: true,
    createdAt: DateTime.now().subtract(const Duration(days: 2, hours: 10)),
  ),
  MessageModel(
    id: 'p1_2',
    content: 'Warm and luxurious. I want a reading corner, natural materials — wood, linen. Something that feels elevated but liveable.',
    isAi: false,
    createdAt: DateTime.now().subtract(const Duration(days: 2, hours: 9, minutes: 50)),
  ),
  MessageModel(
    id: 'p1_3',
    content: 'Got it. Warm walnut, layered lighting, and a proper reading nook — not just a chair in a corner. Japandi base with a more luxurious finish.',
    isAi: true,
    createdAt: DateTime.now().subtract(const Duration(days: 2, hours: 9, minutes: 45)),
  ),
  MessageModel(
    id: 'p1_r1',
    content: 'First vision — I gave the reading corner its own architectural moment, framed in warm walnut with layered indirect lighting. The space already feels significantly more settled. Want to push a direction from here?',
    isAi: true,
    type: MessageType.imageResult,
    result: GeneratedResult(
      beforeImageUrl: 'https://images.unsplash.com/photo-1555041469-a586c61ea9bc?w=800',
      afterImageUrl: 'https://images.unsplash.com/photo-1586023492125-27b2c045efd7?w=800',
      styleLabel: 'Japandi Warm · Vision 1',
      projectId: '1',
    ),
    createdAt: DateTime.now().subtract(const Duration(days: 2, hours: 9, minutes: 30)),
  ),
  // Yesterday
  MessageModel(
    id: 'p1_4',
    content: 'Love it. Can we go more tropical? Add some greenery — bamboo, rattan, Monstera.',
    isAi: false,
    createdAt: DateTime.now().subtract(const Duration(days: 1, hours: 6)),
  ),
  MessageModel(
    id: 'p1_5',
    content: 'Good instinct — the warm walnut base from the first vision actually carries tropical layering really well. I\'ll bring in rattan, Monstera, bamboo, but keep it refined. Not a jungle, just alive.',
    isAi: true,
    createdAt: DateTime.now().subtract(const Duration(days: 1, hours: 5, minutes: 55)),
  ),
  MessageModel(
    id: 'p1_r2',
    content: 'Second vision — the warmth from the first version is still the foundation, but now the space breathes. Monstera near the window adds depth without clutter. Quite different from where you started. Want to take this further or shift direction entirely?',
    isAi: true,
    type: MessageType.imageResult,
    result: GeneratedResult(
      beforeImageUrl: 'https://images.unsplash.com/photo-1555041469-a586c61ea9bc?w=800',
      afterImageUrl: 'https://images.unsplash.com/photo-1556909114-f6e7ad7d3136?w=800',
      styleLabel: 'Tropical Japandi · Vision 2',
      projectId: '1',
    ),
    createdAt: DateTime.now().subtract(const Duration(days: 1, hours: 5, minutes: 40)),
  ),
  // Today
  MessageModel(
    id: 'p1_6',
    content: 'I want modern luxury style បែបកក់ក្តៅ with more natural wood. Something warm and grounded.',
    isAi: false,
    createdAt: DateTime.now().subtract(const Duration(hours: 2, minutes: 30)),
  ),
  MessageModel(
    id: 'p1_7',
    content: 'Understood — keeping the warmth that worked in both previous visions, but pushing the materials into genuine luxury territory. Richer wood grain, deeper earth tones, the kind of layered ambient lighting that makes a room feel expensive even before anyone sits down. That ក្តៅ feeling, but elevated.',
    isAi: true,
    createdAt: DateTime.now().subtract(const Duration(hours: 2, minutes: 25)),
  ),
  MessageModel(
    id: 'p1_r3',
    content: 'Third vision — this is the warmest we\'ve gone. Deep wood grain, earth tones that feel grounded rather than heavy. In the evening, layered lighting like this completely shifts the atmosphere. Does this feel closer to what you had in mind?',
    isAi: true,
    type: MessageType.imageResult,
    result: GeneratedResult(
      beforeImageUrl: 'https://images.unsplash.com/photo-1555041469-a586c61ea9bc?w=800',
      afterImageUrl: 'https://images.unsplash.com/photo-1560184897-ae75f418493e?w=800',
      styleLabel: 'Warm Modern Luxury · Vision 3',
      projectId: '1',
    ),
    createdAt: DateTime.now().subtract(const Duration(hours: 2)),
  ),
];

// ── Project 2 messages: Tropical Villa Facade ─────────────────────────────────
// All today → single "Today" separator

final _p2Messages = [
  MessageModel(
    id: 'p2_1',
    content: 'Strong bones — good geometry and excellent proportions already. The facade reads well; it just needs a complete material and atmosphere redesign. For a genuine Bali Resort arrival, I\'d bring in natural stone cladding, a deeper roof overhang, and tropical planting at the gate to immediately shift the approach experience.',
    isAi: true,
    createdAt: DateTime.now().subtract(const Duration(hours: 4, minutes: 30)),
  ),
  MessageModel(
    id: 'p2_2',
    content: 'I want a full Bali Resort redesign. Tropical entrance, natural materials, water feature if possible.',
    isAi: false,
    createdAt: DateTime.now().subtract(const Duration(hours: 4, minutes: 20)),
  ),
  MessageModel(
    id: 'p2_3',
    content: 'Let\'s go all the way. Natural stone cladding, a water wall at the entry, Pandanus palms at the gate, warm timber windows. The extended overhang gives that sheltered resort feel.',
    isAi: true,
    createdAt: DateTime.now().subtract(const Duration(hours: 4, minutes: 15)),
  ),
  MessageModel(
    id: 'p2_r1',
    content: 'First vision — a significant shift from where you started. Natural stone, tropical planting, the water wall becomes the focal point of the entry. The facade already reads like resort architecture. Want to push the vegetation further, or refine the materiality?',
    isAi: true,
    type: MessageType.imageResult,
    result: GeneratedResult(
      beforeImageUrl: 'https://images.unsplash.com/photo-1568605114967-8130f3a36994?w=800',
      afterImageUrl: 'https://images.unsplash.com/photo-1512917774080-9991f1c4c750?w=800',
      styleLabel: 'Bali Resort · Vision 1',
      projectId: '2',
    ),
    createdAt: DateTime.now().subtract(const Duration(hours: 4)),
  ),
  MessageModel(
    id: 'p2_4',
    content: 'Add more lush vegetation. I want it more immersive — like stepping into a jungle resort.',
    isAi: false,
    createdAt: DateTime.now().subtract(const Duration(hours: 3, minutes: 30)),
  ),
  MessageModel(
    id: 'p2_5',
    content: 'The structure from the first vision gives us exactly the right foundation. I\'ll add a denser tropical canopy — Philodendrons, Heliconia, tree ferns — and let the planting frame the entry rather than obscure it. The water feature stays as the architectural anchor.',
    isAi: true,
    createdAt: DateTime.now().subtract(const Duration(hours: 3, minutes: 25)),
  ),
];

// ── Project 3 messages: Zen Home Office ──────────────────────────────────────
// 7 days ago → "May 4" separator (given today = May 11)

final _p3Messages = [
  MessageModel(
    id: 'p3_1',
    content: 'The window is the room\'s greatest asset — excellent natural light, and that\'s worth building everything around. For a Japandi-focused redesign, I\'d make a walnut slab desk the centrepiece, add integrated storage to eliminate visual noise, and use a warm white and stone palette that lets the daylight do the work.',
    isAi: true,
    createdAt: DateTime.now().subtract(const Duration(days: 7, hours: 3)),
  ),
  MessageModel(
    id: 'p3_2',
    content: 'Clean, minimal, Japandi style. No clutter. I want a focus desk, natural light, calm palette. This is my thinking space.',
    isAi: false,
    createdAt: DateTime.now().subtract(const Duration(days: 7, hours: 2, minutes: 50)),
  ),
  MessageModel(
    id: 'p3_3',
    content: 'Clear brief. Walnut slab desk, low-profile shelving, warm white and stone palette. Nothing unnecessary in the space.',
    isAi: true,
    createdAt: DateTime.now().subtract(const Duration(days: 7, hours: 2, minutes: 45)),
  ),
  MessageModel(
    id: 'p3_r1',
    content: 'Your Zen office — walnut desk, a palette that doesn\'t compete with the daylight, nothing unnecessary in the space. The discipline here is in what we left out. A proper environment for focused, creative work. Want to refine anything, or explore a different direction?',
    isAi: true,
    type: MessageType.imageResult,
    result: GeneratedResult(
      beforeImageUrl: 'https://images.unsplash.com/photo-1593642632559-0c6d3fc62b89?w=800',
      afterImageUrl: 'https://images.unsplash.com/photo-1616594039964-ae9021a400a0?w=800',
      styleLabel: 'Modern Minimalist · Vision 1',
      projectId: '3',
    ),
    createdAt: DateTime.now().subtract(const Duration(days: 7, hours: 2, minutes: 30)),
  ),
];

// ── Featured editorial showcase (hero carousel — not user sessions) ────────────
//
// Curation rules for every pair:
//   BEFORE = plain, un-styled, relatable (real estate listing feel)
//   AFTER  = dramatically aspirational, clearly AI-designed
//   Both sides = same ROOM TYPE (living room → living room, etc.)
//   Visual contrast must be OBVIOUS in under 2 seconds
//
// "Before" IDs sourced from Unsplash search for plain/neutral rooms.
// "After"  IDs are the app's own atmosphere showcase images — already vetted
//          as aspirational and style-distinct.
//
// To swap a pair: change beforeImageUrl or afterImageUrl.
// Verify both sides load and look dramatically different before shipping.

final featuredShowcase = [
  ProjectModel(
    id: 'featured_1',
    title: 'Home — Tropical Villa',
    roomType: 'Living Room',
    style: 'Tropical Luxury',
    beforeImageUrl: 'assets/showcase/villa_before.jpg',
    afterImageUrl: 'assets/showcase/villa_after.jpg',
    status: ProjectStatus.completed,
    createdAt: DateTime(2026, 5, 1),
    lastUpdatedAt: DateTime(2026, 5, 10),
    messages: const [],
    iterationCount: 3,
  ),
  ProjectModel(
    id: 'featured_2',
    title: 'Facade — Night Architecture',
    roomType: 'House Facade',
    style: 'Luxury Night',
    beforeImageUrl: 'assets/showcase/facade_before.jpg',
    afterImageUrl: 'assets/showcase/facade_after.jpg',
    status: ProjectStatus.completed,
    createdAt: DateTime(2026, 4, 28),
    lastUpdatedAt: DateTime(2026, 5, 8),
    messages: const [],
    iterationCount: 4,
  ),
  ProjectModel(
    id: 'featured_3',
    title: 'Apartment — Warm Premium',
    roomType: 'Living Room',
    style: 'Warm Premium',
    beforeImageUrl: 'assets/showcase/apartment_before.jpg',
    afterImageUrl: 'assets/showcase/apartment_after.jpg',
    status: ProjectStatus.completed,
    createdAt: DateTime(2026, 4, 25),
    lastUpdatedAt: DateTime(2026, 5, 5),
    messages: const [],
    iterationCount: 4,
  ),
  ProjectModel(
    id: 'featured_4',
    title: 'Small Space — Cozy Elegant',
    roomType: 'Interior',
    style: 'Cozy Elegant',
    beforeImageUrl: 'assets/showcase/smallspace_before.jpg',
    afterImageUrl: 'assets/showcase/smallspace_after.jpg',
    status: ProjectStatus.completed,
    createdAt: DateTime(2026, 4, 20),
    lastUpdatedAt: DateTime(2026, 5, 2),
    messages: const [],
    iterationCount: 2,
  ),
];

final featuredProject = featuredShowcase.first;

// ── Projects ──────────────────────────────────────────────────────────────────

final mockProjects = [
  ProjectModel(
    id: '1',
    title: 'Warm Japandi Haven',
    roomType: 'Living Room',
    style: 'Japandi',
    beforeImageUrl: 'https://images.unsplash.com/photo-1555041469-a586c61ea9bc?w=800',
    afterImageUrl: 'https://images.unsplash.com/photo-1616046229478-9f05a400b3ed?w=800',
    status: ProjectStatus.completed,
    createdAt: DateTime.now().subtract(const Duration(days: 2, hours: 10)),
    lastUpdatedAt: DateTime.now().subtract(const Duration(hours: 2)),
    iterationCount: 3,
    messages: _p1Messages,
  ),
  ProjectModel(
    id: '2',
    title: 'Bali Villa Transformation',
    roomType: 'House Facade',
    style: 'Bali Resort',
    beforeImageUrl: 'https://images.unsplash.com/photo-1568605114967-8130f3a36994?w=800',
    afterImageUrl: 'https://images.unsplash.com/photo-1600566753190-17f0baa2a6c3?w=800',
    status: ProjectStatus.inProgress,
    createdAt: DateTime.now().subtract(const Duration(hours: 4, minutes: 30)),
    lastUpdatedAt: DateTime.now().subtract(const Duration(hours: 3, minutes: 25)),
    iterationCount: 1,
    messages: _p2Messages,
  ),
  ProjectModel(
    id: '3',
    title: 'Modern Zen Study',
    roomType: 'Home Office',
    style: 'Modern Minimalist',
    beforeImageUrl: 'https://images.unsplash.com/photo-1593642632559-0c6d3fc62b89?w=800',
    afterImageUrl: 'https://images.unsplash.com/photo-1616594039964-ae9021a400a0?w=800',
    status: ProjectStatus.completed,
    createdAt: DateTime.now().subtract(const Duration(days: 7, hours: 3)),
    lastUpdatedAt: DateTime.now().subtract(const Duration(days: 7, hours: 2, minutes: 30)),
    iterationCount: 1,
    messages: _p3Messages,
  ),
];

// ── Chat suggestions ──────────────────────────────────────────────────────────

// Wave 5.11 — atmosphere-neutral architectural defaults. Reads as
// editorial refinement language, not generic AI-tool prompts. Backend
// override path (chat / generation response `suggestions` field) stays
// untouched — these are the calmer fallback list. Per-atmosphere
// contextual mapping deferred to a future wave.
const preGenerationSuggestions = [
  'Push this direction further',
  'Bring in more daylight',
  'Calmer atmosphere',
  'Open the space visually',
];

const postGenerationSuggestions = [
  'Push this direction further',
  'Introduce softer indirect lighting',
  'Try another material palette',
  'Make the atmosphere calmer',
];

// ── Session packs (Wave 5.17d.1 — removed) ────────────────────────────────────
//
// Pre-monetization mock for "Explorer Pass / Design Companion / Architect
// Studio" pay-per-session packs. The credit-pack model was retired in Wave
// 5.17d.1 in favour of the Weekly + Annual Premium subscription via
// RevenueCat (see frontend/lib/features/paywall/paywall_sheet.dart).
// Intentionally left out — do not re-introduce.
