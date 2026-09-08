/// The social-login seam: Facebook, through Supabase, across a full-page
/// redirect — and everything needed to come back honest on the other side.
///
/// Why a redirect changes the shape of the problem
/// -----------------------------------------------
/// Email and phone verify inside one page: the service captures the user id,
/// calls GoTrue, reads the user id again, and states as a FACT whether the
/// person is still the same user. OAuth on the Web leaves the page. The PWA
/// is torn down, Facebook runs, GoTrue runs, and a NEW page boots at the
/// `redirect_to` URL. Nothing in memory survives that.
///
/// So the two halves of the measurement are written down before leaving
/// ([PwaAuthHandoff], in `sessionStorage`) and read back on return
/// ([PwaOAuthReturn], from the boot URL). The service then answers the same
/// question it answers for a code: same user, or a different one?
///
/// Two intents, kept apart on the wire
/// ------------------------------------
///   * SECURE (link)  → `GET /auth/v1/user/identities/authorize` via
///     `linkIdentity`. GoTrue carries the CURRENT user's id in the flow state
///     (`LinkingTargetID`) and attaches the Facebook identity to THAT user.
///     Same `auth.uid()` before and after — nothing to migrate.
///   * SIGN IN        → `GET /auth/v1/authorize` via `signInWithOAuth`. A
///     real sign-in to whichever account owns that Facebook identity. The
///     Guest's session is replaced; the Guest's rows stay where they are.
///
/// One is never turned into the other by this file. A collision on the link
/// path (`identity_already_exists` … "to another user") is reported as the
/// fork it is, and the person chooses the sign-in themselves.
library;

import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../application/pwa_intro_gate.dart' show PwaSessionStore;
import 'pwa_verification_channel.dart';

/// The one social provider this launch ships. An enum rather than a string
/// so a typo cannot select a provider that is not configured.
enum PwaOAuthProviderKind { facebook }

/// Which journey a redirect belongs to. Persisted across the page reload, so
/// the boot code can tell a link from a sign-in WITHOUT inferring it from what
/// the session happens to look like afterwards.
enum PwaOAuthJourney { link, signIn }

/// Starts the provider's screen. Implemented over `supabase_flutter` for real,
/// scripted in tests. Both calls leave the page on the Web; neither returns
/// an outcome, because there is no outcome until the page comes back.
abstract class PwaOAuthGateway {
  /// Attach [provider] to the CURRENT user. Requires a live session.
  /// True when the browser was sent to the provider; false when it could not
  /// be (the URL was minted but the navigation was refused).
  Future<bool> startLink(PwaOAuthProviderKind provider,
      {required String redirectTo});

  /// Sign in to whichever account owns the [provider] identity.
  Future<bool> startSignIn(PwaOAuthProviderKind provider,
      {required String redirectTo});
}

class SupabasePwaOAuthGateway implements PwaOAuthGateway {
  const SupabasePwaOAuthGateway(this._auth);

  final GoTrueClient _auth;

  static OAuthProvider _of(PwaOAuthProviderKind p) => switch (p) {
        PwaOAuthProviderKind.facebook => OAuthProvider.facebook,
      };

  @override
  Future<bool> startLink(PwaOAuthProviderKind provider,
      {required String redirectTo}) {
    // `linkIdentity` = `getLinkIdentityUrl` (authenticated, so GoTrue knows
    // WHICH user to link) + a same-window navigation. PKCE is the SDK default
    // on the Web; the verifier is persisted by supabase_flutter and consumed
    // by the code exchange after the redirect.
    return _auth.linkIdentity(_of(provider), redirectTo: redirectTo);
  }

  @override
  Future<bool> startSignIn(PwaOAuthProviderKind provider,
      {required String redirectTo}) =>
      _auth.signInWithOAuth(_of(provider), redirectTo: redirectTo);
}

// ── The two halves of the measurement ───────────────────────────────────────

/// What was true BEFORE leaving the page. Written by the service, read at boot.
class PwaAuthHandoff {
  const PwaAuthHandoff({
    required this.journey,
    required this.provider,
    required this.userId,
    required this.projectIds,
    required this.startedAtMs,
  });

  final PwaOAuthJourney journey;
  final PwaOAuthProviderKind provider;

  /// The user the browser WAS. For a link, the user it must still be.
  final String userId;

  /// The projects that user could see. Not for restoring anything — for
  /// asserting, afterwards, that a link changed none of them.
  final List<String> projectIds;
  final int startedAtMs;

  static const String storageKey = 'ayden_auth_handoff_v1';

  /// A hand-off older than this is not trusted to explain a boot URL: the
  /// person may have started a flow, closed the tab, and come back to a stale
  /// `?code=` from something else entirely.
  static const Duration maxAge = Duration(minutes: 30);

  bool isFresh(int nowMs) => nowMs - startedAtMs <= maxAge.inMilliseconds;

  Map<String, Object?> toJson() => {
        'journey': journey.name,
        'provider': provider.name,
        'user_id': userId,
        'project_ids': projectIds,
        'started_at_ms': startedAtMs,
      };

  static PwaAuthHandoff? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final j = raw['journey'];
    final p = raw['provider'];
    final u = raw['user_id'];
    final ids = raw['project_ids'];
    final t = raw['started_at_ms'];
    final journey = PwaOAuthJourney.values
        .where((v) => v.name == j)
        .firstOrNull;
    final provider = PwaOAuthProviderKind.values
        .where((v) => v.name == p)
        .firstOrNull;
    if (journey == null || provider == null || u is! String || u.isEmpty) {
      return null;
    }
    return PwaAuthHandoff(
      journey: journey,
      provider: provider,
      userId: u,
      projectIds: ids is List ? ids.whereType<String>().toList() : const [],
      startedAtMs: t is int ? t : 0,
    );
  }

  /// Write to the session store. `sessionStorage` on the Web: survives the
  /// redirect round-trip in the same tab, dies with the tab.
  void save(PwaSessionStore store) =>
      store.write(storageKey, jsonEncode(toJson()));

  /// Read AND clear. A hand-off explains exactly one return; leaving it in
  /// place would let a later, unrelated reload claim a link that never ran.
  static PwaAuthHandoff? take(PwaSessionStore store) {
    final raw = store.read(storageKey);
    if (raw == null || raw.isEmpty) return null;
    store.write(storageKey, '');
    try {
      return fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }
}

/// What the boot URL says about a provider round-trip. Pure parse, no I/O.
///
/// GoTrue answers a PKCE flow with `?code=…` and answers a failure with
/// `error`, `error_code` and `error_description` — in the QUERY and, for now,
/// mirrored in the FRAGMENT (`redirectErrors`, `internal/api/external.go`).
/// Both are read, so a change on GoTrue's side to one or the other cannot
/// turn a collision into silence.
class PwaOAuthReturn {
  const PwaOAuthReturn._({
    required this.hasCode,
    this.error = '',
    this.errorCode = '',
    this.errorDescription = '',
  });

  /// `?code=` was present: the SDK exchanged it during `Supabase.initialize`.
  final bool hasCode;
  final String error;
  final String errorCode;
  final String errorDescription;

  bool get isError => error.isNotEmpty || errorCode.isNotEmpty;

  /// Null when the URL carries no trace of a provider round-trip at all.
  static PwaOAuthReturn? parse(Uri uri) {
    final q = <String, String>{}..addAll(uri.queryParameters);
    if (uri.fragment.isNotEmpty) {
      // The fragment is `a=b&c=d`; parse it as a query, and let the query
      // win where both carry a key (they carry the same values today).
      try {
        final frag = Uri.splitQueryString(uri.fragment);
        for (final e in frag.entries) {
          q.putIfAbsent(e.key, () => e.value);
        }
      } catch (_) {
        // A fragment that is not key=value pairs is not GoTrue's.
      }
    }
    final code = q['code'] ?? '';
    final error = q['error'] ?? '';
    final errorCode = q['error_code'] ?? '';
    final desc = q['error_description'] ?? '';
    if (code.isEmpty && error.isEmpty && errorCode.isEmpty && desc.isEmpty) {
      return null;
    }
    return PwaOAuthReturn._(
      hasCode: code.isNotEmpty,
      error: error,
      errorCode: errorCode,
      errorDescription: desc,
    );
  }

  /// GoTrue's vocabulary → the closed set the UI understands. Static and pure
  /// so every branch can be tested without a browser.
  ///
  /// The one refusal that is a JOURNEY rather than an error is the identity
  /// already belonging to ANOTHER user. GoTrue uses the same code for "already
  /// linked to you" (`identity.go`: "Identity is already linked" vs "…linked
  /// to another user"), so the description is read too — a retry after a
  /// half-finished link must not be shown as a collision with a stranger.
  static PwaVerificationFailure? failureOf(PwaOAuthReturn r) {
    if (!r.isError) return null;
    final code = r.errorCode.toLowerCase();
    final err = r.error.toLowerCase();
    final desc = r.errorDescription.toLowerCase();

    if (code == 'identity_already_exists') {
      return desc.contains('another user')
          ? PwaVerificationFailure.destinationAlreadyRegistered
          : null; // already on THIS account: a success, told twice.
    }
    // The provider's own cancel: Facebook sends `error=access_denied` and
    // GoTrue relays it as an OAuthError with no `error_code` of its own.
    if (err == 'access_denied' &&
        (code.isEmpty || int.tryParse(code) != null) &&
        !desc.contains('signup') &&
        !desc.contains('banned')) {
      return PwaVerificationFailure.cancelled;
    }
    // No usable email from the provider. Two GoTrue shapes: the hard refusal
    // ("Error getting user email from external provider", a 500 with no
    // code) and the link path's `email_not_confirmed` ("Unverified email
    // with facebook"). Both mean the same thing to the person.
    if (code == 'email_not_confirmed' ||
        desc.contains('user email from external provider') ||
        desc.contains('unverified email with')) {
      return PwaVerificationFailure.providerNoEmail;
    }
    if (code == 'email_exists' || code == 'user_already_exists') {
      return PwaVerificationFailure.destinationAlreadyRegistered;
    }
    const config = <String>{
      'manual_linking_disabled',
      'provider_disabled',
      'oauth_provider_not_supported',
      'bad_oauth_callback',
      'bad_oauth_state',
      'flow_state_not_found',
      'flow_state_expired',
      'validation_failed',
      'unexpected_failure',
      'signup_disabled',
    };
    if (config.contains(code)) return PwaVerificationFailure.providerRefused;
    if (err == 'server_error' || err == 'invalid_request') {
      return PwaVerificationFailure.providerRefused;
    }
    return PwaVerificationFailure.unknown;
  }

  /// The same mapping for an exception thrown BEFORE the redirect (the
  /// authenticated `getLinkIdentityUrl` call, or `signInWithOAuth` refusing).
  static PwaVerificationFailure failureOfException(Object e) {
    if (e is AuthException) {
      final code = (e.code ?? '').toLowerCase();
      if (code == 'manual_linking_disabled' ||
          code == 'provider_disabled' ||
          code == 'oauth_provider_not_supported' ||
          code == 'validation_failed') {
        return PwaVerificationFailure.providerRefused;
      }
      if (e is AuthRetryableFetchException) {
        return PwaVerificationFailure.unavailable;
      }
      final status = int.tryParse(e.statusCode ?? '') ?? 0;
      if (status == 0 || status >= 500) {
        return PwaVerificationFailure.unavailable;
      }
      return PwaVerificationFailure.providerRefused;
    }
    return PwaVerificationFailure.unavailable;
  }
}
