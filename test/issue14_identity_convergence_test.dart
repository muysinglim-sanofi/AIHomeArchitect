import 'package:flutter_test/flutter_test.dart';
import 'package:ai_home_architect/core/auth/identity_convergence.dart';
import 'package:ai_home_architect/core/auth/keychain_local_storage.dart';

// ISSUE 14 (2026-08-25) — matrice d'identité.
//
// Le sinistre réel : une session anonyme Supabase de JUIN est redevenue active le
// 2026-08-16 ; l'app a lié RevenueCat dessus ; le renouvellement Weekly du 23/08 a
// été crédité au mauvais compte ; l'abonné payant s'est retrouvé en « Free plan ·
// 0 spaces » face à un paywall d'ACHAT.
//
// Ces tests épinglent la décision PURE qui gouverne toute liaison RevenueCat. Le
// test le plus important est T2b : il rejoue exactement l'incident et exige un
// REFUS. Sans lui, une règle « identité saine ⇒ lier » passerait tous les autres
// tests tout en reproduisant le sinistre.

const String userA = '5d144b46-a439-4feb-8d3b-29c1f5e5cdc2'; // canonique, payant
const String userB = 'eb78d687-367b-456b-857b-4d588b11147c'; // anonyme périmé
const String userC = 'fbc2681c-a171-468f-afa3-d9a8a480e45d'; // invité tout neuf

void main() {
  group('T1 — identités déjà alignées', () {
    test('Supabase A / RC A / saine → aucune action', () {
      expect(
        decideRcBinding(
          supabaseUserId: userA,
          rcAppUserId: userA,
          health: IdentityHealth.canonical,
          rcHasActiveEntitlement: true,
          backendSaysEntitled: true,
        ),
        RcBindAction.noop,
      );
    });

    test('alignées même sans abonnement (invité normal) → aucune action', () {
      expect(
        decideRcBinding(
          supabaseUserId: userC,
          rcAppUserId: userC,
          health: IdentityHealth.canonical,
        ),
        RcBindAction.noop,
      );
    });
  });

  group('T2 — RevenueCat périmé, Supabase correct', () {
    test('RC ne détient AUCUN abonnement → convergence autorisée', () {
      expect(
        decideRcBinding(
          supabaseUserId: userA,
          rcAppUserId: userB,
          health: IdentityHealth.canonical,
          rcHasActiveEntitlement: false,
          backendSaysEntitled: true,
        ),
        RcBindAction.bindToSupabase,
      );
    });

    test(
        'T2b — LE SINISTRE : RC détient l\'abonnement, la cible n\'a RIEN → '
        'REFUS de lier, récupération', () {
      // Rejoue le 2026-08-16 : Supabase = B ressuscité (backend 200 « free »,
      // donc « saine »), RevenueCat = A qui détient le Weekly payé.
      final action = decideRcBinding(
        supabaseUserId: userB,
        rcAppUserId: userA,
        health: IdentityHealth.canonical, // le backend ne voit RIEN d'anormal
        rcHasActiveEntitlement: true,
        backendSaysEntitled: false,
      );
      expect(action, RcBindAction.recoveryRequired);
      expect(action, isNot(RcBindAction.bindToSupabase),
          reason: 'lier ici déplacerait un abonnement payé — c\'est l\'incident');
      expect(requiresIdentityRecovery(action), isTrue);
    });
  });

  group('T3/T4 — identité Supabase FERMÉE (fusionnée)', () {
    test('T3 — Supabase B fusionnée / RC A → JAMAIS de logIn vers B', () {
      final action = decideRcBinding(
        supabaseUserId: userB,
        rcAppUserId: userA,
        health: IdentityHealth.merged,
        rcHasActiveEntitlement: true,
        backendSaysEntitled: false,
      );
      expect(action, RcBindAction.recoveryRequired);
      expect(action, isNot(RcBindAction.bindToSupabase));
    });

    test('T4 — les deux sur B, B fusionnée → récupération, jamais silencieux', () {
      expect(
        decideRcBinding(
          supabaseUserId: userB,
          rcAppUserId: userB,
          health: IdentityHealth.merged,
        ),
        RcBindAction.recoveryRequired,
      );
    });

    test('une identité fermée l\'emporte même sur des identifiants alignés', () {
      // Garde d'ordre : la règle « fermée » passe AVANT la règle « alignées ».
      expect(
        decideRcBinding(
          supabaseUserId: userA,
          rcAppUserId: userA,
          health: IdentityHealth.merged,
        ),
        isNot(RcBindAction.noop),
      );
    });
  });

  group('T5/T6 — nouvel invité', () {
    test('T5 — invité neuf, RevenueCat sans abonnement → parcours normal', () {
      expect(
        decideRcBinding(
          supabaseUserId: userC,
          rcAppUserId: null,
          health: IdentityHealth.canonical,
          rcHasActiveEntitlement: false,
          backendSaysEntitled: false,
        ),
        RcBindAction.bindToSupabase,
      );
    });

    test(
        'T6 — invité neuf MAIS un achat Apple existe déjà → pas de transfert '
        'accidentel vers le nouvel UUID', () {
      expect(
        decideRcBinding(
          supabaseUserId: userC,
          rcAppUserId: userA,
          health: IdentityHealth.canonical,
          rcHasActiveEntitlement: true,
          backendSaysEntitled: false,
        ),
        RcBindAction.recoveryRequired,
      );
    });
  });

  group('T7 — changement d\'identité en cours de session', () {
    test('divergence détectée : la décision ne renvoie jamais noop', () {
      final action = decideRcBinding(
        supabaseUserId: userA,
        rcAppUserId: userB,
        health: IdentityHealth.canonical,
        rcHasActiveEntitlement: false,
        backendSaysEntitled: true,
      );
      expect(action, isNot(RcBindAction.noop),
          reason: 'ensureConfigured ne doit plus conserver l\'ancienne identité');
      expect(action, RcBindAction.bindToSupabase);
    });
  });

  group('T9/T10 — panne réseau ou backend indisponible', () {
    test('T9 — santé inconnue → on conserve l\'existant, aucun transfert', () {
      expect(
        decideRcBinding(
          supabaseUserId: userA,
          rcAppUserId: userB,
          health: IdentityHealth.unknown,
          rcHasActiveEntitlement: true,
          backendSaysEntitled: false,
        ),
        RcBindAction.holdSafe,
      );
    });

    test('T10 — inconnue même sans abonnement en jeu → toujours holdSafe', () {
      expect(
        decideRcBinding(
          supabaseUserId: userC,
          rcAppUserId: null,
          health: IdentityHealth.unknown,
        ),
        RcBindAction.holdSafe,
      );
    });

    test('aucune identité Supabase → rien à lier', () {
      for (final id in <String?>[null, '', '   ']) {
        expect(
          decideRcBinding(
            supabaseUserId: id,
            rcAppUserId: userA,
            health: IdentityHealth.canonical,
          ),
          RcBindAction.holdSafe,
        );
      }
    });
  });

  group('sonde HTTP → verdict de santé', () {
    test('200 → canonique', () {
      expect(healthFromProbe(httpStatus: 200), IdentityHealth.canonical);
    });

    test('403 identity_merged → fermée', () {
      expect(
        healthFromProbe(httpStatus: 403, errorCode: 'identity_merged'),
        IdentityHealth.merged,
      );
    });

    test('403 SANS ce code → inconnue, jamais « fermée » par défaut', () {
      expect(healthFromProbe(httpStatus: 403), IdentityHealth.unknown);
      expect(healthFromProbe(httpStatus: 403, errorCode: 'forbidden'),
          IdentityHealth.unknown);
    });

    test('401 / 5xx / 503 → inconnue (le backend n\'affirme rien)', () {
      for (final s in [401, 500, 502, 503]) {
        expect(healthFromProbe(httpStatus: s), IdentityHealth.unknown,
            reason: 'http $s ne prouve pas une identité saine');
      }
    });

    test('erreur réseau ou statut absent → inconnue', () {
      expect(healthFromProbe(networkError: true), IdentityHealth.unknown);
      expect(healthFromProbe(httpStatus: null), IdentityHealth.unknown);
    });
  });

  group('drapeau de récupération', () {
    setUp(() => identityRecoveryRequired.value = false);

    test('seule une identité fermée arme le drapeau', () {
      applyIdentityVerdict(RcBindAction.noop);
      expect(identityRecoveryRequired.value, isFalse);
      applyIdentityVerdict(RcBindAction.bindToSupabase);
      expect(identityRecoveryRequired.value, isFalse);
      applyIdentityVerdict(RcBindAction.holdSafe);
      expect(identityRecoveryRequired.value, isFalse);
      applyIdentityVerdict(RcBindAction.recoveryRequired);
      expect(identityRecoveryRequired.value, isTrue);
    });

    test('idempotent et réversible', () {
      applyIdentityVerdict(RcBindAction.recoveryRequired);
      applyIdentityVerdict(RcBindAction.recoveryRequired);
      expect(identityRecoveryRequired.value, isTrue);
      applyIdentityVerdict(RcBindAction.noop);
      expect(identityRecoveryRequired.value, isFalse);
    });
  });

  group('clé de session héritée (source de la résurrection)', () {
    test('la clé dérivée reproduit fidèlement le format Supabase', () {
      expect(
        KeychainLocalStorage.legacySessionKeyForUrl(
            'https://vtxkciupyafukhdsgxgw.supabase.co'),
        'sb-vtxkciupyafukhdsgxgw-auth-token',
      );
    });

    test('URL vide → aucune clé, donc aucune migration possible', () {
      expect(KeychainLocalStorage.legacySessionKeyForUrl(''), '');
    });
  });
}
