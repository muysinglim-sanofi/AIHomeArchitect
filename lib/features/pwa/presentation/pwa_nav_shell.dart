/// The bottom navigation shell — iOS `MainShell`, reproduced.
///
/// iOS wraps `/home`, `/projects` and `/profile` in a `ShellRoute` whose only
/// job is a flat, white, hairline-topped `BottomNavigationBar`. The PWA had no
/// equivalent: it hung a language chip, an account chip and a grid icon off a
/// header, which is a web pattern and reads as a different product.
///
/// WHAT THIS PHASE DOES, AND DELIBERATELY DOES NOT
///
/// It builds the shell and wires the two destinations that EXIST. Profile is
/// declared with [PwaNavDestination.profile] and rendered as a real, reachable
/// tab — but tapping it calls whatever `onSelect` the host provides, and no
/// Profile screen is invented here. §5 of the brief is explicit: prepare the
/// architecture, do not introduce fake functionality.
///
/// So a host that has no Profile route yet passes `enabled: false` for it. The
/// tab then renders in the disabled tone and does nothing, which is honest: the
/// destination is coming, and the user is not offered a dead end that throws.
///
/// WHY IT TAKES CALLBACKS RATHER THAN TOUCHING THE ROUTER
///
/// `PwaRoute` / `pwa_url_bridge` own navigation, and this phase is visual
/// infrastructure. A shell that imported the router would couple the design
/// system to the state layer for no benefit. The Home phase wires it up.
library;

import 'package:flutter/material.dart';

import '../l10n/pwa_l10n.dart';
import 'pwa_theme.dart';
import 'pwa_type.dart';

/// The three destinations iOS has, in iOS's order.
enum PwaNavDestination { home, projects, profile }

/// The shell: a body, and the product's bottom navigation under it.
class PwaNavShell extends StatelessWidget {
  const PwaNavShell({
    super.key,
    required this.child,
    required this.current,
    required this.onSelect,
    this.enabled = const {
      PwaNavDestination.home: true,
      PwaNavDestination.projects: true,
      // Phase 8: Profile is a real destination. The `enabled` map stays —
      // a host without the route can still pass false — but the default is
      // now the truth for this app.
      PwaNavDestination.profile: true,
    },
    this.background = pwaCanvas,
  });

  final Widget child;
  final PwaNavDestination current;
  final ValueChanged<PwaNavDestination> onSelect;

  /// Which destinations can actually be reached in this build.
  final Map<PwaNavDestination, bool> enabled;

  final Color background;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      body: child,
      bottomNavigationBar: PwaBottomNav(
        current: current,
        onSelect: onSelect,
        enabled: enabled,
      ),
    );
  }
}

/// The bar itself, separable so a screen can host it without the Scaffold.
///
/// Geometry copied from iOS `MainShell`: `AppColors.surface` fill, a single
/// hairline top border, elevation 0, fixed type, outlined icons that fill when
/// selected.
class PwaBottomNav extends StatelessWidget {
  const PwaBottomNav({
    super.key,
    required this.current,
    required this.onSelect,
    this.enabled = const {},
  });

  final PwaNavDestination current;
  final ValueChanged<PwaNavDestination> onSelect;
  final Map<PwaNavDestination, bool> enabled;

  bool _on(PwaNavDestination d) => enabled[d] ?? true;

  @override
  Widget build(BuildContext context) {
    final l = context.pwaL10n;

    // The labels already exist in the MOBILE dictionary in all three locales
    // (`navHome` / `navProjects` / `navProfile`), and the PWA's l10n facade
    // forwards to it. Re-translating them here would have created a second
    // Khmer vocabulary for the same three words.
    final items = <PwaNavDestination, ({IconData icon, IconData active, String label})>{
      PwaNavDestination.home: (
        icon: Icons.home_outlined,
        active: Icons.home,
        label: l.shared.navHome,
      ),
      PwaNavDestination.projects: (
        icon: Icons.grid_view_outlined,
        active: Icons.grid_view,
        label: l.shared.navProjects,
      ),
      PwaNavDestination.profile: (
        icon: Icons.person_outline,
        active: Icons.person,
        label: l.shared.navProfile,
      ),
    };

    return Container(
      decoration: const BoxDecoration(
        color: pwaCardSurface,
        border: Border(top: BorderSide(color: pwaHairline)),
      ),
      // The home indicator is the bar's problem, not the page's: without this
      // the labels sit in the swipe area on a notched iPhone.
      child: SafeArea(
        top: false,
        // The bar carries the three destinations and NOTHING else. The ABA
        // acceptance lockup rode the Profile label here until ABA's merchant
        // review (2026-09-08) asked for it in the website FOOTER; it now lives
        // in the site footer widget, at the foot of each tab page.
        child: Row(
          children: [
            for (final entry in items.entries)
              Expanded(
                child: _NavItem(
                  icon: entry.value.icon,
                  activeIcon: entry.value.active,
                  label: entry.value.label,
                  selected: entry.key == current,
                  enabled: _on(entry.key),
                  onTap: () => onSelect(entry.key),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // iOS: selected = textPrimary, unselected = textTertiary. A destination
    // that has no screen yet is dimmer still, so it does not read as merely
    // unselected — it reads as not ready.
    final color = !enabled
        ? pwaHairline
        : selected
            ? pwaInk
            : pwaFaint;

    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: label,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(selected ? activeIcon : icon, size: 24, color: color),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: PwaType.navigationLabel(color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
