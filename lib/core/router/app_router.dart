import 'package:flutter/material.dart';
import '../media/ayden_image_source.dart';
import 'package:go_router/go_router.dart';
import '../../features/splash/splash_screen.dart';
import '../../features/onboarding/onboarding_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/upload/upload_screen.dart';
import '../../features/chat/chat_screen.dart';
import '../../features/generation/generation_loading_screen.dart';
import '../../features/result/before_after_screen.dart';
import '../../features/history/projects_history_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/cards/cards_preview_screen.dart';
import '../../shared/widgets/main_shell.dart';

Page<dynamic> _fadePage(Widget child, GoRouterState state) =>
    CustomTransitionPage(
      key: state.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 500),
      reverseTransitionDuration: const Duration(milliseconds: 340),
      transitionsBuilder: (context, animation, _, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      ),
    );

Page<dynamic> _slideUpPage(
  Widget child,
  GoRouterState state,
) => CustomTransitionPage(
  key: state.pageKey,
  child: child,
  transitionDuration: const Duration(milliseconds: 580),
  reverseTransitionDuration: const Duration(milliseconds: 400),
  transitionsBuilder: (context, animation, _, child) {
    final slide = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));
    return FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
      child: SlideTransition(position: slide, child: child),
    );
  },
);

final appRouter = GoRouter(
  // Batch 3.1 — MOBILE router. The web PWA has its own entrypoint
  // (lib/main_pwa.dart), so this router references no features/pwa code and
  // always starts at the mobile splash.
  initialLocation: '/splash',
  routes: [
    GoRoute(
      path: '/splash',
      pageBuilder: (context, state) => _fadePage(const SplashScreen(), state),
    ),
    GoRoute(
      path: '/onboarding',
      pageBuilder: (context, state) =>
          _fadePage(const OnboardingScreen(), state),
    ),
    ShellRoute(
      builder: (context, state, child) => MainShell(child: child),
      routes: [
        GoRoute(
          path: '/home',
          pageBuilder: (context, state) => _fadePage(const HomeScreen(), state),
        ),
        GoRoute(
          path: '/projects',
          pageBuilder: (context, state) =>
              _fadePage(const ProjectsHistoryScreen(), state),
        ),
        GoRoute(
          path: '/profile',
          pageBuilder: (context, state) =>
              _fadePage(const ProfileScreen(), state),
        ),
      ],
    ),
    GoRoute(
      path: '/upload',
      pageBuilder: (context, state) =>
          _slideUpPage(const UploadScreen(), state),
    ),
    GoRoute(
      path: '/chat/:projectId',
      pageBuilder: (context, state) {
        final projectId = state.pathParameters['projectId'] ?? '1';
        final q = state.uri.queryParameters;
        final roomType = q['roomType'];
        final style = q['style'];
        // Wave 4.8.5 — real semantic intent carried as typed flags, never
        // fake "AI Decide"/"Surprise Me" strings. roomType/style are simply
        // omitted by the upload screen when their AI counterpart is chosen.
        final aiDecide = q['aiDecide'] == '1';
        final surprise = q['surprise'] == '1';
        final description = q['desc'];
        // Wave 5.5.14b.2 — bimodal intent forwarded from upload screen.
        // Absent / unknown values fall back to "preserve" (today's behaviour).
        final modeParam = q['mode'];
        final initialMode = modeParam == 'creative' ? 'creative' : 'preserve';
        // Phase A — entered via a "vision ready" notification deep-link. Lets
        // the chat screen bounce cleanly to home if the session was deleted
        // between completion and the tap.
        final fromNotification = q['from'] == 'notif';
        // Batch 1B — safe extraction (no blind `as File?`): a wrong extra type
        // yields null instead of crashing. Carries bytes across navigation.
        final sourceImageFile = AydenImageSource.tryFrom(state.extra);
        return _slideUpPage(
          ChatScreen(
            projectId: projectId,
            initialRoomType: roomType,
            initialStyle: style,
            initialAiDecide: aiDecide,
            initialSurprise: surprise,
            initialDescription: description,
            initialMode: initialMode,
            sourceImageFile: sourceImageFile,
            fromNotification: fromNotification,
          ),
          state,
        );
      },
    ),
    GoRoute(
      path: '/loading',
      pageBuilder: (context, state) =>
          _fadePage(const GenerationLoadingScreen(), state),
    ),
    GoRoute(
      path: '/result/:projectId',
      pageBuilder: (context, state) {
        final projectId = state.pathParameters['projectId'] ?? '1';
        return _slideUpPage(
          BeforeAfterScreen(projectId: projectId, resultExtra: state.extra),
          state,
        );
      },
    ),
    // AYDEN card system preview (dev, flag-gated entry in Profile).
    GoRoute(
      path: '/cards-preview',
      pageBuilder: (context, state) =>
          _fadePage(const CardsPreviewScreen(), state),
    ),
  ],
);
