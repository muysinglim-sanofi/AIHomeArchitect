/// Which GoTrue journey ONE tap on "Continue with Telegram" should start.
///
/// THE PROBLEM, stated exactly
/// ---------------------------
/// GoTrue has two entry points and they are chosen by the URL you leave on:
/// `/user/identities/authorize` attaches the identity to the CURRENT user;
/// `/authorize` signs in as whoever owns it. Which one is right depends on
/// whether this Telegram account is already somebody's — and that is precisely
/// what nobody knows until after the person has authorised at Telegram.
///
/// Guess wrong towards sign-in and a guest's work is left behind. Guess wrong
/// towards link and, when the identity turns out to be taken, GoTrue refuses
/// (`identity_already_exists`), the authorisation is spent, no session is
/// issued — and the only way to the existing account is a SECOND trip through
/// Telegram. That second trip is the whole defect: on a real iPhone it read as
/// "the first login failed", and the tester went round three times.
///
/// Probed against production and staging GoTrue v2.197.0 (2026-09-16):
/// `POST /token?grant_type=id_token` DOES accept `provider=custom:telegram`,
/// but there is no route that attaches an identity from a token —
/// `POST /user/identities` is 404, and `/user/identities/{x}` answers only to
/// DELETE. So a link always costs a browser round trip, and no amount of
/// backend work removes that. One authorisation for every case is not
/// available; one authorisation for every case WE CAN DECIDE IN ADVANCE is.
///
/// SO THIS FILE DECIDES IN ADVANCE, on the only honest ground there is: what
/// the guest would lose. A guest carrying nothing loses nothing by being signed
/// in as somebody — so sign-in is safe whichever way the identity turns out,
/// and it is one trip either way. A guest carrying anything at all is linked,
/// exactly as before.
///
/// FAIL CLOSED. Every clause below must be positively true, read from the
/// SERVER, before sign-in is chosen. An unread entitlement, an unrestored
/// library, a wallet that does not add up — any of them means link, because
/// link never loses anything and the cost of being wrong the other way is
/// somebody's work.
///
/// This is Telegram's decision and Telegram's alone. Facebook keeps the journey
/// its own screen asks for, unchanged.
library;

import 'pwa_oauth_gateway.dart' show PwaOAuthJourney;

/// What the SERVER says this guest is carrying, at the moment they tapped.
///
/// Every field is an answer that came back from the backend — the entitlement
/// read and the restored library — never a local guess. [entitlementKnown] and
/// [libraryRestored] exist so that "we have not been told yet" is a state of
/// its own, and not silently read as a zero.
class PwaGuestFootprint {
  const PwaGuestFootprint({
    required this.entitlementKnown,
    required this.libraryRestored,
    required this.projects,
    required this.visions,
    required this.freeCredits,
    required this.passCredits,
    required this.creditsAvailable,
    required this.hasActivePass,
  });

  /// The one that is never safe to abandon: nothing is known.
  static const PwaGuestFootprint unknown = PwaGuestFootprint(
    entitlementKnown: false,
    libraryRestored: false,
    projects: 0,
    visions: 0,
    freeCredits: 0,
    passCredits: 0,
    creditsAvailable: 0,
    hasActivePass: false,
  );

  /// True once the Billing Engine's answer has actually arrived.
  final bool entitlementKnown;

  /// True once the server's library answer has arrived. A boot that has not
  /// finished restoring reports zero projects, and zero must not be believed.
  final bool libraryRestored;

  final int projects;
  final int visions;
  final int freeCredits;
  final int passCredits;
  final int creditsAvailable;
  final bool hasActivePass;

  /// Whether abandoning this guest would cost its owner nothing.
  ///
  /// Read the clauses as one sentence: we have been told about this account,
  /// and what we were told is that it holds no work, no purchase, no pass, a
  /// wallet that adds up, and a free trial it has not started spending.
  ///
  /// The trial is the subtle one. A fresh guest has NO ledger row and NO wallet
  /// row at all — the 3 Spaces it displays are a projection the Billing Engine
  /// makes for an account that has never held anything (`_free_bucket_available`
  /// adds the trial only while no TRIAL row exists). So abandoning a guest in
  /// this state leaves nothing behind to orphan, and the account it becomes is
  /// projected the same trial by the same rule: 3 before, 3 after, once.
  bool get nothingToLose =>
      entitlementKnown &&
      libraryRestored &&
      projects == 0 &&
      visions == 0 &&
      !hasActivePass &&
      passCredits == 0 &&
      // No paid entitlement can exist here anyway — a Guest may not buy — but
      // it is asserted rather than assumed.
      creditsAvailable == freeCredits &&
      // A wallet that does not add up is an anomaly, and an anomaly is a doubt.
      creditsAvailable > 0;
}

/// The journey one tap should start.
///
/// [userAskedSignIn] is the person having said so themselves, on the "already
/// have an account?" door. It is honoured first and without qualification:
/// they told us, so nothing here needs to infer it.
PwaOAuthJourney pwaTelegramJourneyFor({
  required bool isAnonymous,
  required bool userAskedSignIn,
  required PwaGuestFootprint footprint,
}) {
  if (userAskedSignIn) return PwaOAuthJourney.signIn;
  // An account that is already somebody's is ADDING Telegram to itself. Signing
  // in would swap the person out of the account they are standing in.
  if (!isAnonymous) return PwaOAuthJourney.link;
  return footprint.nothingToLose
      ? PwaOAuthJourney.signIn
      : PwaOAuthJourney.link;
}
