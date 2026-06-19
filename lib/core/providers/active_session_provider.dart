import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Group 1 (2026-06-19) — the chat session the user is CURRENTLY viewing in the
/// foreground (its project id), or null when no chat is visible / the app is
/// backgrounded.
///
/// A generation's completion handler runs on the ORIGINAL widget, which is
/// `!mounted` once the user navigates away — but `!mounted` is ALSO true when
/// the user has navigated back to a freshly-recreated instance of the SAME
/// session. Using `!mounted` alone as "user is elsewhere" therefore wrongly
/// fires a "ready" snackbar / OS notification for the session the user is
/// actively looking at. This app-scoped signal lets the completion paths ask
/// the real question — "is the just-completed session the one on screen?" — and
/// suppress the notify accordingly (the inline reconciliation shows the result).
///
/// Set by ChatScreen when it becomes visible (initState for a real session +
/// on resume); cleared on dispose and when the app is backgrounded.
final activeSessionProvider = StateProvider<String?>((ref) => null);
