import 'package:flutter_test/flutter_test.dart';
import 'package:ai_home_architect/features/chat/chat_screen.dart';

// STRUCTURAL_CAPTURE_MODE kill-switch (2026-07-07) — frontend cleanup guarantee.
// Proves every authoritative source (a /generate|/refine reply OR a ledger/version
// entry) that carries an EMPTY identity CLEARS the stale local token, so no stale
// passport survives in off mode — while double mode keeps the historical behaviour.
void main() {
  group('adoptStructuralIdentity (pure decision)', () {
    test('disabled flag → efface, quel que soit le local', () {
      expect(adoptStructuralIdentity('OLD', 'X', true), '');
      expect(adoptStructuralIdentity('OLD', '', true), '');
      expect(adoptStructuralIdentity('OLD', null, true), '');
    });

    test('champ ABSENT (null) → conserve le local (legacy / reconcile sans le champ)',
        () {
      expect(adoptStructuralIdentity('OLD', null, false), 'OLD');
      expect(adoptStructuralIdentity('', null, false), '');
    });

    test('champ PRÉSENT vide ("") → efface le token périmé (pas de no-op)', () {
      expect(adoptStructuralIdentity('OLD_TOKEN', '', false), '');
    });

    test('champ PRÉSENT non vide → adopté (double, comportement historique)', () {
      expect(adoptStructuralIdentity('OLD', 'NEW_TOKEN', false), 'NEW_TOKEN');
    });
  });

  group('lookupStructuralTokenInLedger (pure) — navigation/reconcile', () {
    const url = 'https://cdn/proj/v2.jpg';
    String ledger(String token) =>
        '[{"generated_image_url":"$url","structural_identity_token":"$token"}]';

    test('version trouvée, token vide (lignée off) → "" (déclenche l\'effacement)',
        () {
      expect(lookupStructuralTokenInLedger(ledger(''), url), '');
    });

    test('version trouvée, token présent (lignée double) → le token', () {
      expect(lookupStructuralTokenInLedger(ledger('TOK_ABC'), url), 'TOK_ABC');
    });

    test('match par PATH en ignorant la query string (tokens signés)', () {
      expect(lookupStructuralTokenInLedger(ledger('TOK'), '$url?sig=xyz'), 'TOK');
    });

    test('URL absente du ledger → null (conserve le local)', () {
      expect(lookupStructuralTokenInLedger(ledger('TOK'), 'https://cdn/proj/v9.jpg'),
          isNull);
    });

    test('ledger vide / malformé / afterUrl vide → null', () {
      expect(lookupStructuralTokenInLedger('', url), isNull);
      expect(lookupStructuralTokenInLedger('{not json', url), isNull);
      expect(lookupStructuralTokenInLedger(ledger('TOK'), ''), isNull);
    });
  });

  group('composition — le vrai chemin de restauration', () {
    const url = 'https://cdn/proj/v2.jpg';
    String ledger(String token) =>
        '[{"generated_image_url":"$url","structural_identity_token":"$token"}]';

    test(
        'ancien token local + navigation vers une version off (ledger "") → état "" '
        '→ la prochaine V2 enverra structural_identity=""', () {
      const localBefore = 'OLD_TOKEN';
      final fromLedger = lookupStructuralTokenInLedger(ledger(''), '$url?sig=1');
      final localAfter = adoptStructuralIdentity(localBefore, fromLedger, false);
      expect(localAfter, ''); // token périmé effacé → V2 postera ""
    });

    test('reconcile >60s : payload SANS le champ identité → local conservé', () {
      // Un GeneratedResult reconstruit qui n\'inclut pas structural_identity.
      final Map<String, dynamic> reconciled = {'after_image_url': url};
      final returned = reconciled['structural_identity'] as String?; // null
      final captureDisabled = reconciled['structural_capture_disabled'] == true;
      expect(adoptStructuralIdentity('OLD', returned, captureDisabled), 'OLD');
    });

    test('reconcile en off : payload avec structural_capture_disabled=true → efface',
        () {
      final Map<String, dynamic> reconciled = {
        'after_image_url': url,
        'structural_identity': '',
        'structural_capture_disabled': true,
      };
      final returned = reconciled['structural_identity'] as String?;
      final captureDisabled = reconciled['structural_capture_disabled'] == true;
      expect(adoptStructuralIdentity('OLD', returned, captureDisabled), '');
    });

    test('rollback double : navigation vers une version double → token restauré', () {
      final fromLedger = lookupStructuralTokenInLedger(ledger('DOUBLE_TOK'), url);
      expect(adoptStructuralIdentity('X', fromLedger, false), 'DOUBLE_TOK');
    });
  });
}
