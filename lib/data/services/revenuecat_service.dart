/// Wave 5.17d — RevenueCat purchases service.
///
/// Single source of truth for the subscription state and purchase /
/// restore actions. Wraps `purchases_flutter` so the rest of the app
/// never imports the SDK directly — easier to mock, easier to swap.
///
/// App User ID
///   The RevenueCat App User ID is bound to the Supabase anonymous
///   UUID (Decision D6). Purchases follow the UUID across launches
///   (Supabase persists the session locally) ; on reinstall the UUID
///   resets and the user must Restore Purchases (Decision D8).
///
/// Premium entitlement
///   The single V1 entitlement is `premium`. Active iff RC reports
///   `customerInfo.entitlements.active['premium']` non-null AND its
///   expiration is in the future (RC handles grace periods).
///
/// Webhook path
///   On purchase success, RC fires `INITIAL_PURCHASE` to the backend
///   `/webhooks/revenuecat` endpoint. The backend UPSERTs the
///   `user_roles` row that the quota module consults. The frontend
///   does NOT write to user_roles directly — RC is the source of
///   truth and the backend is the authority.
///
/// Configuration
///   - `REVENUECAT_PUBLIC_API_KEY_IOS`     in .env
///   - `REVENUECAT_PUBLIC_API_KEY_ANDROID` in .env
///   - Apple/Google products created in App Store Connect + Play
///     Console (operational ; not code).
///   - Entitlement `premium` defined in the RC dashboard with two
///     products attached (Wave 5.17d.1 re-pivot, 2026-05-31) :
///       • Weekly product   → PackageType.weekly  → $7.99 / week
///       • Annual product   → PackageType.annual  → $79.99 / year
///     The paywall sheet picks both via `_selectPackages(offering)` and
///     renders Weekly (gold, MOST POPULAR) + Annual (green, BEST VALUE)
///     side by side on wide screens / stacked on small screens.
library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../core/feature_flags.dart';

/// Premium entitlement identifier. Must match the entitlement defined
/// in the RevenueCat dashboard.
const String kPremiumEntitlement = 'premium';

/// Thrown by purchase / restore actions when the SDK is not configured
/// (typically because `revenuecatGracefulDegradation = true` skipped
/// `Purchases.configure()` at boot due to missing API keys). The
/// PaywallSheet catches this and renders a clean message — instead of
/// the raw native "Singleton not initialised" stacktrace that bubbles
/// up otherwise.
class RevenuecatNotConfiguredException implements Exception {
  const RevenuecatNotConfiguredException();
  @override
  String toString() => 'RevenueCat SDK is not configured on this device.';
}

/// Résultat CLASSIFIÉ d'une tentative d'achat (Lot 2 — upgrade Weekly → Annual).
///  • activated : le PRODUIT EXACT visé est actif après l'achat.
///  • cancelled : UNIQUEMENT `PurchasesErrorCode.purchaseCancelledError`.
///  • failed    : retour normal SANS le produit visé, ou toute autre erreur.
enum PurchaseAttempt { activated, cancelled, failed }

/// Preuve PURE (testable sans SDK) que le produit EXACT est actif après un achat.
/// ⚠️ Ne PAS se contenter de « entitlement premium actif » : un abonné Weekly possède
/// DÉJÀ `premium` avant l'upgrade → seul le product-id exact démontre l'achat de l'Annual.
/// Vrai ssi `expectedProductId` figure dans les abonnements actifs OU est le produit porteur
/// de l'entitlement premium.
bool annualPurchaseActivated({
  required List<String> activeSubscriptions,
  String? premiumProductId,
  required String expectedProductId,
}) =>
    activeSubscriptions.contains(expectedProductId) || premiumProductId == expectedProductId;

class RevenuecatService {
  RevenuecatService._();
  static final RevenuecatService instance = RevenuecatService._();

  bool _configured = false;
  bool _premiumActive = false;
  Offerings? _offerings;
  // FAST_BOOT — dedupes a configure() that runs fire-and-forget at boot so the
  // paywall can await the SAME in-flight call instead of starting a second one.
  Future<void>? _configuring;

  final StreamController<bool> _premiumController =
      StreamController<bool>.broadcast();

  /// Emits `true` when premium becomes active, `false` when it lapses.
  /// Subscribe in widgets that need to react to subscription changes
  /// (paywall, profile screen, lock UI).
  Stream<bool> get premiumStream => _premiumController.stream;

  /// Current premium status. Re-checked on every CustomerInfo update
  /// from the SDK ; cached locally so callers don't have to await.
  bool get isPremium => _premiumActive;

  /// True iff `Purchases.configure()` has completed successfully. False
  /// when the SDK is in degraded mode (missing API key + graceful flag).
  /// Callers should consult this before showing "Subscribe" / "Restore"
  /// affordances as enabled.
  bool get isConfigured => _configured;

  /// Cached offerings from the last fetch. Use `loadOfferings()` to
  /// refresh ; widgets typically call it on paywall mount.
  Offerings? get offerings => _offerings;

  /// Configure the SDK once at app start (called from main.dart after
  /// Supabase anonymous sign-in completes). Binds the App User ID to
  /// the Supabase UUID. Subsequent calls are no-ops unless [userId]
  /// changed.
  ///
  /// Throws on misconfiguration (missing API key) UNLESS
  /// `FeatureFlags.revenuecatGracefulDegradation` is true, in which
  /// case the error is logged and the service stays disabled (no
  /// premium ever, purchase flows fail with a clear error).
  Future<void> configure({required String userId}) async {
    if (_configured) {
      // Re-bind only on actual UUID change (e.g. after Restore).
      try {
        await Purchases.logIn(userId);
      } catch (e) {
        debugPrint('[RevenuecatService] logIn re-bind failed: $e');
      }
      return;
    }

    final apiKey = _selectApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      if (FeatureFlags.revenuecatGracefulDegradation) {
        debugPrint(
          '[RevenuecatService] DEGRADED — no API key for ${Platform.operatingSystem}. '
          'Premium will not work. Set REVENUECAT_PUBLIC_API_KEY_IOS / _ANDROID in .env.',
        );
        return;
      }
      throw StateError(
        'RevenueCat API key missing for ${Platform.operatingSystem}. '
        'Set REVENUECAT_PUBLIC_API_KEY_IOS or REVENUECAT_PUBLIC_API_KEY_ANDROID '
        'in frontend/.env, or flip FeatureFlags.revenuecatGracefulDegradation '
        'to true (NOT recommended outside hot-fix).',
      );
    }

    await Purchases.setLogLevel(
      kDebugMode ? LogLevel.debug : LogLevel.warn,
    );

    final config = PurchasesConfiguration(apiKey)
      ..appUserID = userId;
    await Purchases.configure(config);

    Purchases.addCustomerInfoUpdateListener(_onCustomerInfoUpdated);

    // Prime the initial state so widgets that read isPremium before
    // any purchase event see the correct value.
    try {
      final info = await Purchases.getCustomerInfo();
      _onCustomerInfoUpdated(info);
    } catch (e) {
      debugPrint('[RevenuecatService] initial getCustomerInfo failed: $e');
    }

    _configured = true;
    debugPrint(
      '[RevenuecatService] configured — user=$userId platform=${Platform.operatingSystem}',
    );
    // [IDENTITY][RC_AFTER_CONFIG] — l'appUserID RC DOIT == user_id Supabase (D6). Un mismatch
    // expliquerait un restore_required chronique (l'achat suit un autre id que le user courant).
    try {
      final appUserId = await Purchases.appUserID;
      debugPrint('[IDENTITY][RC_AFTER_CONFIG] app_user_id=$appUserId '
          'expected_user_id=$userId match=${appUserId == userId} configured=$_configured');
    } catch (_) {/* best-effort */}
  }

  /// FAST_BOOT — idempotent + awaitable configure. The boot path calls this
  /// fire-and-forget (un-awaited); the paywall calls it AWAITED before loading
  /// offerings, so it either no-ops (already configured), joins the in-flight
  /// boot call, or starts one. Never throws to the caller (errors are logged in
  /// configure under graceful degradation; a non-graceful StateError would
  /// surface, but boot/paywall both wrap this).
  Future<void> ensureConfigured({required String userId}) {
    if (_configured) return Future<void>.value();
    return _configuring ??=
        configure(userId: userId).whenComplete(() => _configuring = null);
  }

  /// Fetch the current offerings (products configured for this app in
  /// RC). Cached in [offerings] ; callers can read the cache after the
  /// first await. Returns null on failure (graceful : paywall handles
  /// the empty state).
  Future<Offerings?> loadOfferings() async {
    if (!_configured) {
      debugPrint(
        '[RevenuecatService] loadOfferings called before configure — returning null',
      );
      return null;
    }
    try {
      _offerings = await Purchases.getOfferings();
      return _offerings;
    } catch (e) {
      debugPrint('[RevenuecatService] getOfferings failed: $e');
      return null;
    }
  }

  /// Lot 2 — résout le package **Annual** de l'offering courant (MÊME source que le
  /// paywall : `findByType(PackageType.annual)` sur `current.availablePackages`, cf.
  /// `paywall_sheet.dart`). Renvoie `null` si le SDK n'est pas configuré, si les
  /// offerings sont indisponibles, ou si aucun package Annual n'existe → l'appelant
  /// (Premium Center) MASQUE proprement le CTA « Upgrade to Annual ». N'achète rien.
  Future<Package?> annualPackage() async {
    final offerings = await loadOfferings();
    final pkgs = offerings?.current?.availablePackages ?? const <Package>[];
    for (final p in pkgs) {
      if (p.packageType == PackageType.annual) return p;
    }
    // Log explicite (sans donnée sensible) : le CTA Upgrade sera masqué proprement.
    debugPrint(
      '[RevenuecatService] annual package unavailable in current offering '
      '(offering=${offerings?.current?.identifier ?? 'none'}, '
      'packages=${pkgs.length}) — Upgrade CTA hidden',
    );
    return null;
  }

  /// Lot 2 — achat de l'UPGRADE Annual, CLASSIFIÉ par le PRODUIT EXACT visé (`annualPkg`).
  /// N'AFFECTE PAS le parcours d'achat Weekly ([purchasePackage] reste inchangé).
  ///
  /// ⚠️ On ne conclut JAMAIS « activated » sur « premium actif » : un abonné Weekly a déjà
  /// l'entitlement `premium`. On exige que `annualPkg.storeProduct.identifier` soit RÉELLEMENT
  /// actif après l'achat (`activeSubscriptions` ou produit porteur de `premium`). Un booléen
  /// `false` n'est PLUS traité comme une annulation silencieuse :
  ///   • `purchaseCancelledError`        → cancelled
  ///   • produit Annual exact confirmé   → activated
  ///   • retour normal SANS l'Annual     → failed
  ///   • toute autre exception           → failed
  Future<PurchaseAttempt> purchaseAnnual(Package annualPkg) async {
    if (!_configured) return PurchaseAttempt.failed;
    final String expectedId = annualPkg.storeProduct.identifier;
    try {
      final CustomerInfo info = await Purchases.purchasePackage(annualPkg);
      final ok = annualPurchaseActivated(
        activeSubscriptions: info.activeSubscriptions,
        premiumProductId: info.entitlements.active[kPremiumEntitlement]?.productIdentifier,
        expectedProductId: expectedId,
      );
      if (!ok) {
        debugPrint('[RevenuecatService] purchaseAnnual: premium may be active but exact '
            'product not confirmed (expected=$expectedId) — treated as failed');
      }
      return ok ? PurchaseAttempt.activated : PurchaseAttempt.failed;
    } on PlatformException catch (e) {
      final code = PurchasesErrorHelper.getErrorCode(e);
      return code == PurchasesErrorCode.purchaseCancelledError
          ? PurchaseAttempt.cancelled
          : PurchaseAttempt.failed;
    } on RevenuecatNotConfiguredException {
      return PurchaseAttempt.failed;
    } catch (_) {
      return PurchaseAttempt.failed;
    }
  }

  /// Trigger a purchase. On success the CustomerInfo listener fires +
  /// updates `_premiumActive` + emits on `premiumStream`. The webhook
  /// path (RC → backend → user_roles) runs in parallel ; the next
  /// /generate call sees the new premium row.
  ///
  /// Returns true iff the purchase completed (entitlement active).
  /// Returns false for user-cancel ; throws on actual error. Throws
  /// [RevenuecatNotConfiguredException] when the SDK was never
  /// configured (degraded mode) — caller renders a clean message.
  Future<bool> purchasePackage(Package pkg) async {
    if (!_configured) {
      throw const RevenuecatNotConfiguredException();
    }
    final result = await Purchases.purchasePackage(pkg);
    final active = result.entitlements.active[kPremiumEntitlement];
    return active != null;
  }

  /// Restore prior purchases on this device (Apple/Google account-bound).
  /// Used on a fresh install when the user previously bought premium.
  ///
  /// Returns true iff a premium entitlement was restored. Throws on
  /// network or store errors ; never throws on "no purchases found"
  /// (that just returns false). Throws
  /// [RevenuecatNotConfiguredException] when the SDK was never
  /// configured (degraded mode) — caller renders a clean message
  /// instead of the native "Singleton not initialised" stacktrace.
  Future<bool> restorePurchases() async {
    if (!_configured) {
      throw const RevenuecatNotConfiguredException();
    }
    final info = await Purchases.restorePurchases();
    final active = info.entitlements.active[kPremiumEntitlement];
    // [RESTORE][RC_RESULT] — le CustomerInfo n'existe QUE ici (les call-sites jettent la
    // valeur). Trace ce que RC voit réellement : entitlement, produit, uid d'origine
    // (détecte un achat sous un ANCIEN user_id = RC transfer), expiration, abos actifs.
    debugPrint('[RESTORE][RC_RESULT] entitlement_active=${active != null} '
        'product_id=${active?.productIdentifier} '
        'original_app_user_id=${info.originalAppUserId} '
        'latest_expiration=${active?.expirationDate ?? info.latestExpirationDate} '
        'active_subscriptions=${info.activeSubscriptions}');
    return active != null;
  }

  /// Premium Center (Lot 1) — URL de gestion de l'abonnement fournie par le store
  /// (App Store / Google Play) via RevenueCat. `null` si non configuré, en erreur, ou
  /// AUCUN abonnement store actif (ex : promo, sandbox) → l'appelant masque le bouton
  /// « Manage Subscription » proprement. N'entre dans AUCUNE décision de billing.
  Future<String?> managementUrl() async {
    if (!_configured) return null;
    try {
      final info = await Purchases.getCustomerInfo();
      return info.managementURL;
    } catch (e) {
      debugPrint('[RevenuecatService] managementUrl failed (non-fatal): $e');
      return null;
    }
  }

  /// Re-bind RC to a new App User ID. Called after sign-in flows that
  /// change the Supabase UUID. Sign-in is hidden in V1
  /// (FeatureFlags.signInEnabled=false) so this is dormant.
  Future<void> logIn(String userId) async {
    if (!_configured) return;
    await Purchases.logIn(userId);
  }

  // ── Internal ──────────────────────────────────────────────────────────

  String? _selectApiKey() {
    if (Platform.isIOS) {
      return dotenv.env['REVENUECAT_PUBLIC_API_KEY_IOS'];
    }
    if (Platform.isAndroid) {
      return dotenv.env['REVENUECAT_PUBLIC_API_KEY_ANDROID'];
    }
    return null;
  }

  void _onCustomerInfoUpdated(CustomerInfo info) {
    final active = info.entitlements.active[kPremiumEntitlement];
    final newState = active != null;
    if (newState != _premiumActive) {
      _premiumActive = newState;
      debugPrint(
        '[RevenuecatService] premium state changed → $_premiumActive',
      );
      _premiumController.add(newState);
    }
  }
}
