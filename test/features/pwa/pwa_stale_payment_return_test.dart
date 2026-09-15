/// PAY01-PAY16 — a payment result is only news to the person who asked for it.
///
/// THE INCIDENT, 2026-09-15 (production)
/// -------------------------------------
/// A checkout was opened on 13/09 and abandoned: ABA never created the
/// transaction, nobody paid, the tab closed. It stayed OPEN in the rail for two
/// days, because the rail is only reconciled when somebody asks. On 15/09 at
/// 08:49:43 the app was opened, `restore()` asked `GET /payments/open`, the
/// server did exactly the right thing — Check Transaction, NOT_CREATED,
/// terminal — and the PWA answered that correct verdict with a full-screen
/// "Payment failed / cancelled" and "No credits were added". Eight seconds
/// later a new checkout was started: somebody had pressed Try again.
///
/// Nothing about the money was wrong. The sentence was.
///
/// WHAT THESE TESTS PIN
/// --------------------
///   * the server stays authoritative about payment STATUS — `restore()` is
///     not disabled, stale attempts are still reconciled, GRANTED is still
///     terminal (PAY05, PAY06, PAY12);
///   * the client is authoritative about whether that status INTERRUPTS
///     someone, and carries the distinction explicitly rather than guessing it
///     from the age of a tran_id (PAY05-PAY07, PAY13);
///   * a recovered SUCCESS is never suppressed — the whole reason `restore()`
///     exists is the person who paid, closed the tab, and would otherwise never
///     find out (PAY14);
///   * no technical, auth or availability error may impersonate a financial
///     failure (PAY08-PAY11).
library;

import 'package:ai_home_architect/core/l10n/app_localizations.dart';
import 'package:ai_home_architect/features/pwa/billing/pwa_entitlement_controller.dart';
import 'package:ai_home_architect/features/pwa/billing/pwa_payment.dart';
import 'package:ai_home_architect/features/pwa/billing/pwa_payment_controller.dart';
import 'package:ai_home_architect/features/pwa/data/mock_pwa_experience_repository.dart';
import 'package:ai_home_architect/features/pwa/data/pwa_mock_generation_service.dart';
import 'package:ai_home_architect/features/pwa/application/pwa_controller.dart';
import 'package:ai_home_architect/features/pwa/l10n/pwa_l10n.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_experience.dart';
import 'package:ai_home_architect/features/pwa/presentation/pwa_payment_result.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// ── doubles ──────────────────────────────────────────────────────────────────

Map<String, Object?> _row(String state, {String reason = ''}) => {
      'ok': true,
      'tran_id': 'A084c1b6aa64dffdf439',
      'state': state,
      'sku': 'pack_10',
      'credits': 10,
      'amount': 1.99,
      'currency': 'USD',
      'checkout_url': '',
      'checkout_mode': 'plugin',
      'expires_at':
          DateTime.now().add(const Duration(minutes: 30)).toIso8601String(),
      'failure_reason': reason,
      'poll_interval_ms': 1000,
    };

/// `GET /payments/open` answering with a stale attempt the SERVER has just
/// reconciled — the shape production actually returned at 08:49:43.
Map<String, Object?> _open(String state, {String reason = ''}) =>
    {..._row(state, reason: reason), 'open': true};

/// A refusal, in the backend's own machine vocabulary.
Map<String, Object?> _err(String code, {int status = 400}) =>
    {'ok': false, 'http_status': status, 'error_code': code};

class _Server {
  _Server({this.checkout, this.open, this.cancel, List<Map<String, Object?>>? polls})
      : _polls = List.of(polls ?? const []);

  Map<String, Object?>? checkout;
  Map<String, Object?>? open;
  Map<String, Object?>? cancel;
  final List<Map<String, Object?>> _polls;
  Map<String, Object?>? _last;

  final calls = <String>[];

  PwaPaymentGateway get gateway => PwaPaymentGateway(
        startCheckout: ({required String sku, required String attemptKey}) async {
          calls.add('checkout:$sku:$attemptKey');
          return checkout ?? _row('AWAITING_PAYMENT');
        },
        orderStatus: (t) async {
          calls.add('status');
          if (_polls.isNotEmpty) _last = _polls.removeAt(0);
          return _last ?? _row('AWAITING_PAYMENT');
        },
        openOrder: () async {
          calls.add('open');
          return open ?? const {'ok': true, 'open': false};
        },
        cancelOrder: (t) async {
          calls.add('cancel');
          return cancel ?? _row('CANCELLED');
        },
      );
}

int _grants = 0;

PwaPaymentController _controller(_Server s) =>
    PwaPaymentController(s.gateway, () async => _grants++);

void main() {
  setUp(() => _grants = 0);

  // ══════════════════════════════════════════════════════════════════════════
  group('ACTIVE  a checkout the person just started reports everything', () {
    test('PAY01 APPROVED/GRANTED — success, attributed to the active journey',
        () async {
      final s = _Server(checkout: _row('GRANTED'));
      final c = _controller(s);
      addTearDown(c.dispose);
      await c.start('pack_10');

      expect(c.state.state, PwaPaymentState.granted);
      expect(c.state.origin, PwaPaymentOrigin.activeCheckout);
      expect(pwaPaymentAnnouncementFor(c.state.state, c.state.origin),
          PwaPaymentAnnouncement.success);
      // The ONE side effect a payment is allowed to have, exactly once.
      expect(_grants, 1);
    });

    test('PAY02 a genuine FAILED still shows the failure card', () async {
      final s = _Server(checkout: _row('FAILED', reason: 'DECLINED'));
      final c = _controller(s);
      addTearDown(c.dispose);
      await c.start('pack_10');

      expect(c.state.state, PwaPaymentState.failed);
      expect(c.state.origin, PwaPaymentOrigin.activeCheckout);
      expect(pwaPaymentAnnouncementFor(c.state.state, c.state.origin),
          PwaPaymentAnnouncement.failure,
          reason: 'this person is waiting on this answer');
      expect(_grants, 0);
    });

    test('PAY03 CANCELLED — the server verified first, and the card is shown',
        () async {
      final s = _Server(cancel: _row('CANCELLED'));
      final c = _controller(s);
      addTearDown(c.dispose);
      await c.start('pack_10');
      await c.cancel();

      expect(s.calls.contains('cancel'), isTrue,
          reason: 'cancel goes through the server: money that landed wins');
      expect(c.state.state, PwaPaymentState.cancelled);
      expect(pwaPaymentAnnouncementFor(c.state.state, c.state.origin),
          PwaPaymentAnnouncement.failure);
    });

    test('PAY04 EXPIRED during an active checkout is reported', () async {
      final s = _Server(checkout: _row('EXPIRED', reason: 'EXPIRED'));
      final c = _controller(s);
      addTearDown(c.dispose);
      await c.start('pack_10');

      expect(c.state.state, PwaPaymentState.expired);
      expect(pwaPaymentAnnouncementFor(c.state.state, c.state.origin),
          PwaPaymentAnnouncement.failure);
    });

    test('PAY16 retry keeps the attempt; start over mints a new one', () async {
      final s = _Server();
      final c = _controller(s);
      addTearDown(c.dispose);
      await c.start('pack_10');
      final first = c.attemptKey;
      await c.retry('pack_10');
      expect(c.attemptKey, first, reason: 'same attempt, same PayWay tran_id');

      await c.start('pack_10');
      expect(c.attemptKey, isNot(first));
      expect(c.state.origin, PwaPaymentOrigin.activeCheckout);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  group('RESTORE  a verdict nobody asked for is reconciled, not announced', () {
    test(
        'PAY05 stale NOT_CREATED — the server IS asked, the person is not '
        'interrupted', () async {
      final s = _Server(open: _open('FAILED', reason: 'NOT_CREATED'));
      final c = _controller(s);
      addTearDown(c.dispose);
      await c.restore();

      // The reconciliation must still happen: `GET /payments/open` runs Check
      // Transaction server-side, which is what terminalises the stale row.
      expect(s.calls, contains('open'));
      expect(c.state.state, PwaPaymentState.failed,
          reason: 'the backend verdict is preserved, not rewritten');
      expect(c.state.origin, PwaPaymentOrigin.restore);
      expect(pwaPaymentAnnouncementFor(c.state.state, c.state.origin),
          PwaPaymentAnnouncement.none);
      expect(pwaPaymentFailureIsRestored(c.state.state, c.state.origin), isTrue);
    });

    test('PAY06 stale EXPIRED — same', () async {
      final s = _Server(open: _open('EXPIRED', reason: 'EXPIRED'));
      final c = _controller(s);
      addTearDown(c.dispose);
      await c.restore();

      expect(c.state.state, PwaPaymentState.expired);
      expect(pwaPaymentAnnouncementFor(c.state.state, c.state.origin),
          PwaPaymentAnnouncement.none);
    });

    test('PAY07 age is NOT the discriminator — intent is', () async {
      // A stale attempt reconciled the instant the app opens is "young"; a
      // genuine checkout somebody leaves open for half an hour is "old". Only
      // who asked tells them apart, so that is what is carried.
      for (final expires in [
        DateTime.now().subtract(const Duration(days: 3)),
        DateTime.now().add(const Duration(minutes: 30)),
      ]) {
        final body = _open('FAILED', reason: 'NOT_CREATED')
          ..['expires_at'] = expires.toIso8601String();
        final s = _Server(open: body);
        final c = _controller(s);
        addTearDown(c.dispose);
        await c.restore();
        expect(pwaPaymentAnnouncementFor(c.state.state, c.state.origin),
            PwaPaymentAnnouncement.none,
            reason: 'restored: silent whatever the clock says');
      }
      // The mirror: an ancient ACTIVE checkout is still the person's news.
      final old = _row('FAILED', reason: 'NOT_CREATED')
        ..['expires_at'] =
            DateTime.now().subtract(const Duration(days: 3)).toIso8601String();
      final s = _Server(checkout: old);
      final c = _controller(s);
      addTearDown(c.dispose);
      await c.start('pack_10');
      expect(pwaPaymentAnnouncementFor(c.state.state, c.state.origin),
          PwaPaymentAnnouncement.failure);
    });

    test('PAY14 a RESTORED success is never suppressed', () async {
      // The production path this exists for: pay, close the tab, come back.
      // `/payments/open` verifies before answering, so the grant is already
      // done by the time the browser hears about it.
      final s = _Server(open: _open('GRANTED'));
      final c = _controller(s);
      addTearDown(c.dispose);
      await c.restore();

      expect(c.state.state, PwaPaymentState.granted);
      expect(c.state.origin, PwaPaymentOrigin.restore);
      expect(pwaPaymentAnnouncementFor(c.state.state, c.state.origin),
          PwaPaymentAnnouncement.success,
          reason: 'losing a recovered success costs the person money');
      expect(_grants, 1, reason: 'entitlement is re-read on a restored grant');
    });

    test('PAY12 a GRANTED purchase can never be shown as failed afterwards',
        () async {
      final s = _Server(checkout: _row('GRANTED'));
      final c = _controller(s);
      addTearDown(c.dispose);
      await c.start('pack_10');
      expect(c.state.state, PwaPaymentState.granted);

      // Continue -> reset -> the later cold start. The rail keeps GRANTED out
      // of the OPEN set, so `/payments/open` has nothing to return.
      c.reset();
      s.open = const {'ok': true, 'open': false};
      await c.restore();

      expect(c.state.state, PwaPaymentState.idle);
      expect(pwaPaymentAnnouncementFor(c.state.state, c.state.origin),
          PwaPaymentAnnouncement.none);
      expect(_grants, 1, reason: 'granted once, and only once');
    });

    test('PAY13 a success plus an unrelated stale attempt', () async {
      final s = _Server(checkout: _row('GRANTED'));
      final c = _controller(s);
      addTearDown(c.dispose);
      await c.start('pack_10');
      expect(pwaPaymentAnnouncementFor(c.state.state, c.state.origin),
          PwaPaymentAnnouncement.success);

      // The next boot finds the OTHER attempt — abandoned days ago, correctly
      // terminalised by the server, and nothing at all to do with the pack
      // this person now owns.
      c.reset();
      s.open = _open('FAILED', reason: 'NOT_CREATED');
      await c.restore();

      expect(c.state.state, PwaPaymentState.failed,
          reason: 'the stale row is still reconciled');
      expect(pwaPaymentAnnouncementFor(c.state.state, c.state.origin),
          PwaPaymentAnnouncement.none,
          reason: 'and says nothing about the pack they bought');
      expect(_grants, 1);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  group('VOCABULARY  a technical refusal never impersonates a decline', () {
    /// Every refusal the backend can put on a payment route, as a state.
    PwaPayment parsed(String code) => PwaPayment.parse(_err(code));

    test('PAY08 SESSION_EXPIRED is an AUTH error, not a failed payment', () {
      expect(pwaClassifyPaymentError('SESSION_EXPIRED'),
          PwaPaymentErrorClass.auth);
      final p = parsed('SESSION_EXPIRED');
      expect(p.state, isNot(PwaPaymentState.failed));
      expect(p.state, PwaPaymentState.unreachable);
      // The scenario in the brief: paid yesterday, cold start today, token
      // aged out, `GET /payments/open` answers 401.
      for (final origin in PwaPaymentOrigin.values) {
        expect(pwaPaymentAnnouncementFor(p.state, origin),
            PwaPaymentAnnouncement.none,
            reason: 'no card, no "no credits were added"');
      }
      expect(pwaPaymentResultKindFor(p.state), isNull);
    });

    test('PAY09 PAYMENTS_CLOSED is availability, not a decline', () {
      expect(pwaClassifyPaymentError('PAYMENTS_CLOSED'),
          PwaPaymentErrorClass.availability);
      final p = parsed('PAYMENTS_CLOSED');
      expect(p.state, PwaPaymentState.unavailable);
      expect(pwaPaymentResultKindFor(p.state), isNull);
    });

    test('PAY10 both spellings of "unavailable" mean the same thing', () {
      for (final code in ['PAYMENT_UNAVAILABLE', 'PAYMENTS_UNAVAILABLE']) {
        expect(pwaClassifyPaymentError(code),
            PwaPaymentErrorClass.availability,
            reason: '$code: the backend has both, they are one meaning');
        expect(parsed(code).state, PwaPaymentState.unavailable);
        expect(pwaPaymentResultKindFor(parsed(code).state), isNull);
      }
    });

    test('PAY11 contract errors are not verdicts either', () {
      for (final code in ['UNKNOWN_TRANSACTION', 'BAD_REQUEST']) {
        expect(pwaClassifyPaymentError(code), PwaPaymentErrorClass.contract);
        expect(parsed(code).state, isNot(PwaPaymentState.failed));
        expect(pwaPaymentResultKindFor(parsed(code).state), isNull);
      }
    });

    test('PAY11b the whole vocabulary: only a REFUSED purchase is a failure',
        () {
      const everything = [
        'SESSION_EXPIRED',
        'MISSING_TOKEN',
        'PAYMENTS_CLOSED',
        'PAYMENTS_UNAVAILABLE',
        'PAYMENT_UNAVAILABLE',
        'UNKNOWN_TRANSACTION',
        'BAD_REQUEST',
        'UNKNOWN_PRODUCT',
        'PRODUCT_NOT_WEB_SELLABLE',
        'PRODUCT_NOT_PRICED',
        'UNREACHABLE',
        'PAYMENT_PROVIDER_UNREACHABLE',
        'CANCELLED',
        // The one the backend has not invented yet. It must not be a decline
        // either — that default is the point of the whole classification.
        'SOME_CODE_ADDED_NEXT_YEAR',
        '',
      ];
      for (final code in everything) {
        expect(parsed(code).state, isNot(PwaPaymentState.failed),
            reason: '$code must not render as "payment failed"');
      }
      // …and the gateway actually refusing the purchase still does.
      expect(pwaClassifyPaymentError('PAYMENT_PROVIDER_REFUSED'),
          PwaPaymentErrorClass.payment);
      expect(parsed('PAYMENT_PROVIDER_REFUSED').state, PwaPaymentState.failed);
      // CHECKOUT_BUSY is not an error at all: the server is already on it.
      expect(parsed('CHECKOUT_BUSY').state, PwaPaymentState.created);
    });

    test('a 2xx body is still read exactly as the server wrote it', () {
      // The classification touches refusals ONLY. Authoritative terminal
      // states keep arriving in the `state` field and keep meaning what they
      // said — the backend remains the authority on payment status.
      for (final (raw, want) in const [
        ('GRANTED', PwaPaymentState.granted),
        ('FAILED', PwaPaymentState.failed),
        ('EXPIRED', PwaPaymentState.expired),
        ('CANCELLED', PwaPaymentState.cancelled),
        ('AWAITING_PAYMENT', PwaPaymentState.awaitingPayment),
        ('VERIFIED', PwaPaymentState.verified),
      ]) {
        expect(PwaPayment.parse(_row(raw)).state, want);
      }
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  group('THE SCREEN  what actually appears on a cold start', () {
    Widget app(ProviderContainer c) => MediaQuery(
          data: const MediaQueryData(
              disableAnimations: true, size: Size(390, 844)),
          child: UncontrolledProviderScope(
            container: c,
            child: const MaterialApp(
              locale: Locale('fr'),
              localizationsDelegates: [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: [Locale('en'), Locale('km'), Locale('fr')],
              home: PwaExperience(),
            ),
          ),
        );

    ProviderContainer container(_Server s) {
      final repo = MockPwaExperienceRepository(workDelay: Duration.zero);
      return ProviderContainer(overrides: [
        pwaRepositoryProvider.overrideWithValue(repo),
        pwaGenerationServiceProvider
            .overrideWithValue(PwaMockGenerationService(repo)),
        pwaEntitlementReaderProvider.overrideWithValue(() async => null),
        pwaPaymentGatewayProvider.overrideWithValue(s.gateway),
      ]);
    }

    testWidgets('PAY05/PAY07 a stale attempt reconciled at boot shows NOTHING',
        (tester) async {
      final s = _Server(open: _open('FAILED', reason: 'NOT_CREATED'));
      final c = container(s);
      addTearDown(c.dispose);
      await tester.pumpWidget(app(c));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }

      expect(s.calls, contains('open'),
          reason: 'restore() is NOT disabled — the row is still reconciled');
      expect(find.byKey(const ValueKey('pwa-pay-result-failure')), findsNothing);
      final l = pwaL10nFor(const Locale('fr'));
      expect(find.text(l.payResultFailedTitle), findsNothing);
      expect(find.text(l.payResultFailedBody), findsNothing);
    });

    testWidgets('PAY14/PAY15 a restored SUCCESS appears, exactly once',
        (tester) async {
      final s = _Server(open: _open('GRANTED'));
      final c = container(s);
      addTearDown(c.dispose);
      await tester.pumpWidget(app(c));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }

      expect(find.byKey(const ValueKey('pwa-pay-result-success')), findsOneWidget,
          reason: 'somebody who paid and walked away must be told');
      expect(find.byKey(const ValueKey('pwa-pay-result-failure')), findsNothing);

      // More frames, and more rebuilds, do not produce a second card.
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
      expect(find.byKey(const ValueKey('pwa-pay-result-success')), findsOneWidget);
    });

    testWidgets('PAY08 SESSION_EXPIRED at boot shows no payment failure',
        (tester) async {
      final s = _Server(open: _err('SESSION_EXPIRED', status: 401));
      final c = container(s);
      addTearDown(c.dispose);
      await tester.pumpWidget(app(c));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }

      expect(find.byKey(const ValueKey('pwa-pay-result-failure')), findsNothing);
      final l = pwaL10nFor(const Locale('fr'));
      expect(find.text(l.payResultFailedTitle), findsNothing);
      expect(find.text(l.payResultFailedBody), findsNothing);
    });
  });
}
