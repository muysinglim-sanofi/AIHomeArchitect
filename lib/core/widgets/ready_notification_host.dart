import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_colors.dart';
import '../l10n/app_localizations.dart';
import '../providers/active_session_provider.dart';
import '../providers/pending_generations_provider.dart';
import '../router/app_router.dart';

/// BUG 2 + BUG 3 (2026-07-09) — notification in-app « ready » GLOBALE, tappable,
/// session-aware. Remplace l'ancienne snackbar Home-scoped NON tappable.
///
/// Règles métier (validées) :
///   • User sur le CHAT de la session qui finit → RIEN ici (le résultat s'affiche
///     inline). Garanti en amont : `readyUnseen` n'est jamais posé pour la
///     session active (activeSessionProvider). [BUG-2 chat]
///   • User sur HOME → RIEN ici : le badge « Ready » de la carte session est le
///     signal EN PLACE, un popup serait redondant. [BUG-2 Home]
///   • User AILLEURS (autre session, profil, projets…) → snackbar TAPPABLE ; tap
///     = ouvre la bonne session. [BUG-3]
///
/// Monté UNE fois dans `MaterialApp.router(builder:)` → écoute route-agnostique
/// (l'ancienne snackbar ne se déclenchait que sur la route Home).
class ReadyNotificationHost extends ConsumerWidget {
  final Widget child;
  const ReadyNotificationHost({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<Map<String, GenerationLifecycle>>(
      pendingGenerationsProvider,
      (previous, next) {
        for (final entry in next.entries) {
          final String sessionId = entry.key;
          final GenerationLifecycle newState = entry.value;
          final GenerationLifecycle? prevState = previous?[sessionId];
          if (prevState == newState) continue;

          // Ne réagir qu'aux transitions de COMPLÉTION (jamais markInFlight).
          final bool isReady = newState == GenerationLifecycle.readyUnseen &&
              prevState != GenerationLifecycle.readyUnseen;
          final bool isError = newState == GenerationLifecycle.errorUnseen &&
              prevState != GenerationLifecycle.errorUnseen;
          if (!isReady && !isError) continue;

          // BUG-2 (chat) : l'utilisateur regarde CETTE session → inline, pas de notif.
          if (ref.read(activeSessionProvider) == sessionId) continue;
          // BUG-2 (Home) : le badge de la carte est le signal en place → pas de popup.
          final String path =
              appRouter.routerDelegate.currentConfiguration.uri.path;
          if (path == '/home') continue;

          _showReadyBanner(context, sessionId: sessionId, isError: isError);
        }
      },
    );
    return child;
  }

  void _showReadyBanner(
    BuildContext context, {
    required String sessionId,
    required bool isError,
  }) {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars(); // une seule notif à la fois
    messenger.showSnackBar(
      SnackBar(
        content: Text(isError ? l10n.homeDesignFailed : l10n.homeDesignReady),
        backgroundColor: isError ? AppColors.error : AppColors.textPrimary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 88),
        duration: const Duration(seconds: 5),
        // BUG-3 : tappable → ouvre la bonne session (le chat efface le badge à l'ouverture).
        action: isError
            ? null
            : SnackBarAction(
                label: l10n.notifViewAction,
                onPressed: () => appRouter.push('/chat/$sessionId?from=notif'),
              ),
      ),
    );
  }
}
