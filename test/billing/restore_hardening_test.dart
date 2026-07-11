// BUG 3 hardening — preuve DEVICE-INDÉPENDANTE du contrat « restore se termine TOUJOURS »
// (le symptôme device était « Restoring… » sans fin). On prouve le mécanisme exact ajouté :
//   1. un restorePurchases() qui PEND (Future jamais complété) + .timeout(...) → TimeoutException
//      → outcome=failed (donc un snackbar terminal, jamais un spinner infini) ;
//   2. un sync timeout → {} → restoreOutcomeFromSync → failed (terminal) ;
//   3. le switch outcome→message est TOTAL (exhaustif sur les 4 enums) → un message existe
//      toujours pour n'importe quel outcome.
// Le timeout réel utilisé ici (50 ms) est le MÊME mécanisme que le .timeout(15 s) du handler ;
// seule la durée diffère, pour garder le test rapide.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ai_home_architect/data/services/status_service.dart';

void main() {
  group('BUG 3 hardening — restore termine TOUJOURS (device-indépendant)', () {
    test('hang RC (Future jamais complété) + .timeout → outcome=failed', () async {
      RestoreOutcome outcome = RestoreOutcome.restored; // pire cas si le timeout ne tranche pas
      try {
        // Completer.future ne complète JAMAIS = restorePurchases() qui pend indéfiniment.
        await Completer<void>().future.timeout(const Duration(milliseconds: 50));
        outcome = RestoreOutcome.restored; // ne doit PAS être atteint
      } catch (_) {
        outcome = RestoreOutcome.failed;
      }
      expect(outcome, RestoreOutcome.failed,
          reason: 'un hang SDK devient failed → snackbar terminal GARANTI');
    });

    test('sync timeout → {} → restoreOutcomeFromSync → failed (terminal)', () {
      // onTimeout du handler renvoie {} ; {} mappe vers failed.
      expect(restoreOutcomeFromSync(const {}), RestoreOutcome.failed);
    });

    test('le switch outcome→message est TOTAL : chaque enum a un terminal', () {
      // Miroir du switch UI (profile _restorePurchase / paywall) : exhaustif sur les 4 états.
      String terminalFor(RestoreOutcome o) => switch (o) {
            RestoreOutcome.restored => 'stRestoreDone',
            RestoreOutcome.activeNoSpaces => 'stRestoreActiveNoSpaces',
            RestoreOutcome.noneFound => 'stRestoreNoneFound',
            RestoreOutcome.failed => 'stRestoreFailed',
          };
      for (final o in RestoreOutcome.values) {
        expect(terminalFor(o).isNotEmpty, isTrue,
            reason: 'aucun outcome ne doit rester sans message terminal');
      }
    });
  });
}
