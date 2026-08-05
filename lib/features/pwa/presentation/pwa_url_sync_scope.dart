/// Batch 3.4b — the live state↔URL synchroniser (PWA-only).
///
/// Wraps the PWA shell and keeps the browser address bar and the controller in
/// lock-step, using the injectable [PwaUrlBridge] abstraction (never a web-only
/// import — the History-API impl is supplied by `main_pwa`; tests inject the
/// in-memory fake). Three jobs, nothing more:
///   • state change → push the new durable URL (replace on fallback/normalization);
///   • Back/Forward (popstate) → apply the URL back onto the controller;
///   • first frame → normalize the boot URL to the controller's canonical route.
/// It is loop-guarded: a change that leaves the URL already-correct is a no-op.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/pwa_controller.dart';
import '../application/pwa_route.dart';
import '../application/pwa_url_bridge.dart';

class PwaUrlSyncScope extends ConsumerStatefulWidget {
  const PwaUrlSyncScope({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<PwaUrlSyncScope> createState() => _PwaUrlSyncScopeState();
}

class _PwaUrlSyncScopeState extends ConsumerState<PwaUrlSyncScope> {
  late final PwaUrlBridge _bridge;

  /// Set while applying a Back/Forward URL so the resulting reconciliation, if it
  /// normalizes to a *different* route, replaces rather than pushes (no dup entry).
  bool _fromHistory = false;

  /// Guards against scheduling more than one reconcile per microtask.
  bool _reconcileScheduled = false;

  @override
  void initState() {
    super.initState();
    _bridge = ref.read(pwaUrlBridgeProvider);
    _bridge.onPop(_onPop);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Normalize the boot URL to the first-frame canonical route (replace only).
      final canonical = ref.read(pwaControllerProvider).canonicalRoute.location;
      if (_locationOf(_bridge.current()) != canonical) {
        _bridge.replace(canonical);
      }
    });
  }

  void _onPop(Uri uri) {
    _fromHistory = true;
    ref.read(pwaControllerProvider.notifier).applyRoute(PwaRoute.parse(uri));
    // Reconcile once even if applyRoute was a no-op (route already current): this
    // consumes `_fromHistory` AND drops a stale query the state no longer maps to
    // (e.g. Back onto ?vision=V after V became the current vision).
    _scheduleReconcile();
  }

  /// A controller mutation happened. Do NOT react to it directly — a single user
  /// action can emit several synchronous state assignments (e.g. openLibrary saves
  /// the active project, still in `architect`, THEN switches to `projects`), and
  /// reacting to an intermediate phase corrupts history. Instead coalesce into ONE
  /// reconcile that reads the SETTLED state after the current microtask drains.
  void _onState(PwaState? prev, PwaState next) => _scheduleReconcile();

  void _scheduleReconcile() {
    if (_reconcileScheduled) return;
    _reconcileScheduled = true;
    scheduleMicrotask(() {
      _reconcileScheduled = false;
      if (mounted) _reconcileUrl();
    });
  }

  /// Bring the address bar in line with the current (settled) canonical route.
  void _reconcileUrl() {
    final canonical = ref.read(pwaControllerProvider).canonicalRoute.location;
    final fromHistory = _fromHistory;
    _fromHistory = false;
    if (_locationOf(_bridge.current()) == canonical) return; // already correct
    // Replace (no new entry) for a Back/Forward normalization or when the URL's
    // project just disappeared (delete-current, §3); push for a normal nav.
    if (fromHistory || _currentUrlProjectGone()) {
      _bridge.replace(canonical);
    } else {
      _bridge.push(canonical);
    }
  }

  /// True when the address bar still points at a project route whose id is no
  /// longer in the library (the open project was just deleted).
  bool _currentUrlProjectGone() {
    final id = PwaRoute.parse(_bridge.current()).projectId;
    if (id == null) return false;
    return !ref
        .read(pwaControllerProvider)
        .library
        .any((p) => p.projectId == id);
  }

  String _locationOf(Uri u) =>
      u.query.isEmpty ? u.path : '${u.path}?${u.query}';

  @override
  void dispose() {
    _bridge.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<PwaState>(pwaControllerProvider, _onState);
    return widget.child;
  }
}
