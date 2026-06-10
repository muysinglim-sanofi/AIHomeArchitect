/// AYDEN card system — preview/validation screen (isolated, flag-gated route).
/// Renders the full visual system on the real assets so the layout/typo/feel
/// can be validated on device before wiring into the real upload flow.
///
/// ROOMS = 2-col grid (Indoor / Outdoor sub-grids, neutral, sans-caps, no
/// number) · ATMOSPHERES = mini-hero carousel (serif + italic subtitle, warm) ·
/// AI = black ✦. Selection here is demo-only (local state).
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'card_catalog.dart';
import 'widgets/ai_action_card.dart';
import 'widgets/atmosphere_hero_card.dart';
import 'widgets/room_card.dart';

class CardsPreviewScreen extends StatefulWidget {
  const CardsPreviewScreen({super.key});

  @override
  State<CardsPreviewScreen> createState() => _CardsPreviewScreenState();
}

class _CardsPreviewScreenState extends State<CardsPreviewScreen> {
  static const _canvas = Color(0xFF0B0B0C);
  String? _selRoom;
  String? _selAtmo;

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;

    // Hero card sizing (4:3, taller/cinematic). Secondary cards = ~78% height
    // to make the hierarchy instantly readable (featured vs library).
    final cols = w >= 600 ? 3 : 2;
    final heroCardW = (w - 32 - (cols - 1) * 12) / cols;
    final heroCardH = heroCardW / 1.2; // ~6:5 — taller / cinematic
    final secH = heroCardH * 0.78;
    final secW = secH * 1.2;

    // Atmosphere carousel — taller cinematic card + ~20% next-card peek.
    final atmoCardW = w * 0.80;
    final atmoHeight = atmoCardW / 1.2;

    return Scaffold(
      backgroundColor: _canvas,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
          children: [
            // Back
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                onPressed: () =>
                    context.canPop() ? context.pop() : context.go('/home'),
                icon: const Icon(Icons.arrow_back, color: Colors.white),
              ),
            ),

            // ── ROOMS — Featured (hero grid) + Library (More Spaces row) ──
            _sectionHeader('ROOMS', 'CHOOSE THE SPACE'),
            const SizedBox(height: 14),
            _heroGrid(context),
            const SizedBox(height: 24),
            _moreSpacesHeader(),
            const SizedBox(height: 12),
            _moreSpacesRow(secW, secH),

            // Luxury comes from space — generous gap before Atmospheres.
            const SizedBox(height: 44),

            // ── ATMOSPHERES ────────────────────────────────────────────
            _sectionHeader('ATMOSPHERES', 'CHOOSE THE FEELING'),
            const SizedBox(height: 14),
            SizedBox(
              height: atmoHeight,
              child: PageView.builder(
                controller: PageController(viewportFraction: 0.80),
                padEnds: false,
                itemCount: kAtmosphereCards.length + 1,
                itemBuilder: (context, i) {
                  final isLast = i == kAtmosphereCards.length;
                  return Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: isLast
                        ? AiActionCard(
                            title: 'Surprise Me',
                            subtitle: 'Discover an unexpected atmosphere',
                            radius: 18,
                            onTap: () => setState(() => _selAtmo = '__ai__'),
                          )
                        : _atmoCard(kAtmosphereCards[i]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _atmoCard(AtmosphereCardData a) => AtmosphereHeroCard(
        name: a.name,
        subtitle: a.subtitle,
        asset: a.asset,
        selected: _selAtmo == a.id,
        onTap: () => setState(() => _selAtmo = a.id),
      );

  // Featured hero grid — 6 large cards, 4:3 (cinematic, breathing room).
  // Responsive: 3 columns on wide (tablet/desktop) → 2 rows; 2 on phones.
  Widget _heroGrid(BuildContext context) {
    final cols = MediaQuery.sizeOf(context).width >= 600 ? 3 : 2;
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: cols,
      childAspectRatio: 6 / 5, // taller / cinematic (≈ +11% height)
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      children: [
        for (final r in kHeroRooms)
          RoomCard(
            label: r.label,
            asset: r.asset,
            selected: _selRoom == r.id,
            onTap: () => setState(() => _selRoom = r.id),
          ),
      ],
    );
  }

  // Library — secondary horizontal row (~78% of hero height) + AI Decide.
  Widget _moreSpacesRow(double cardW, double cardH) {
    return SizedBox(
      height: cardH,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        clipBehavior: Clip.none,
        itemCount: kMoreRooms.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          if (i == kMoreRooms.length) {
            return SizedBox(
              width: cardW,
              child: AiActionCard(
                title: 'AI Decide',
                subtitle: 'Let AI choose the perfect room',
                onTap: () => setState(() => _selRoom = '__ai__'),
              ),
            );
          }
          final r = kMoreRooms[i];
          return SizedBox(
            width: cardW,
            child: RoomCard(
              label: r.label,
              asset: r.asset,
              selected: _selRoom == r.id,
              onTap: () => setState(() => _selRoom = r.id),
            ),
          );
        },
      ),
    );
  }

  // Intentional, curated library header — "More Spaces →".
  Widget _moreSpacesHeader() => Row(
        children: [
          Text(
            'More Spaces',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 14,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(width: 6),
          Icon(Icons.arrow_forward,
              size: 15, color: Colors.white.withValues(alpha: 0.5)),
        ],
      );

  Widget _sectionHeader(String title, String subtitle) => Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.45),
              fontSize: 11,
              fontWeight: FontWeight.w500,
              letterSpacing: 1.0,
            ),
          ),
        ],
      );

}
