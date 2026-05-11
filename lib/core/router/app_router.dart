import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../features/splash/splash_screen.dart';
import '../../features/onboarding/onboarding_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/upload/upload_screen.dart';
import '../../features/chat/chat_screen.dart';
import '../../features/generation/generation_loading_screen.dart';
import '../../features/result/before_after_screen.dart';
import '../../features/history/projects_history_screen.dart';
import '../../features/sessions/buy_sessions_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../shared/widgets/main_shell.dart';

Page<dynamic> _fadePage(Widget child, GoRouterState state) => CustomTransitionPage(
      key: state.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 500),
      reverseTransitionDuration: const Duration(milliseconds: 340),
      transitionsBuilder: (context, animation, _, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      ),
    );

Page<dynamic> _slideUpPage(Widget child, GoRouterState state) => CustomTransitionPage(
      key: state.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 580),
      reverseTransitionDuration: const Duration(milliseconds: 400),
      transitionsBuilder: (context, animation, _, child) {
        final slide = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        );
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: SlideTransition(position: slide, child: child),
        );
      },
    );

final appRouter = GoRouter(
  initialLocation: '/splash',
  routes: [
    GoRoute(
      path: '/splash',
      pageBuilder: (context, state) => _fadePage(const SplashScreen(), state),
    ),
    GoRoute(
      path: '/onboarding',
      pageBuilder: (context, state) => _fadePage(const OnboardingScreen(), state),
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
          pageBuilder: (context, state) => _fadePage(const ProjectsHistoryScreen(), state),
        ),
        GoRoute(
          path: '/profile',
          pageBuilder: (context, state) => _fadePage(const ProfileScreen(), state),
        ),
      ],
    ),
    GoRoute(
      path: '/upload',
      pageBuilder: (context, state) => _slideUpPage(const UploadScreen(), state),
    ),
    GoRoute(
      path: '/chat/:projectId',
      pageBuilder: (context, state) {
        final projectId = state.pathParameters['projectId'] ?? '1';
        final roomType = state.uri.queryParameters['roomType'];
        final style = state.uri.queryParameters['style'];
        return _slideUpPage(
          ChatScreen(projectId: projectId, initialRoomType: roomType, initialStyle: style),
          state,
        );
      },
    ),
    GoRoute(
      path: '/loading',
      pageBuilder: (context, state) => _fadePage(const GenerationLoadingScreen(), state),
    ),
    GoRoute(
      path: '/result/:projectId',
      pageBuilder: (context, state) {
        final projectId = state.pathParameters['projectId'] ?? '1';
        return _slideUpPage(BeforeAfterScreen(projectId: projectId), state);
      },
    ),
    GoRoute(
      path: '/sessions',
      pageBuilder: (context, state) => _slideUpPage(const BuySessionsScreen(), state),
    ),
  ],
);
